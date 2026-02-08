#!/usr/bin/env bash

set -e # e: exit if any command has a non-zero exit status
# set -x # x: all executed commands are printed to the terminal
set -u # u: all references to variables that have not been previously defined cause an error

BOOTSTRAP_TERRAFORM_HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  bootstrap_terraform.sh \
    --terraform-version <version> \
    --aws-provider-version <version> \
    --company <name> \
    --repository-url <url> \
    --aws-profile <profile> \
    --aws-region <region> \
    --project <name> \
    [--environments "production, staging, development"]

Required:
  --terraform-version
  --aws-provider-version
  --company
  --repository-url
  --aws-profile
  --aws-region
  --project

Optional:
  --environments    Comma-separated list (default: "production")
  -h, --help        Show this help
EOF
}

ensure_value() {
  local opt="$1"
  local arg_count="$2"
  local val="${3-}"
  if [[ "$arg_count" -lt 2 || -z "$val" ]]; then
    echo "Missing value for ${opt}" >&2
    usage
    exit 1
  fi
}

missing_deps=()
for cmd in aws terraform envsubst; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing_deps+=("$cmd")
  fi
done

if [[ ${#missing_deps[@]} -gt 0 ]]; then
  echo "Missing required commands: ${missing_deps[*]}" >&2
  echo "Please install the missing dependencies and retry." >&2
  exit 1
fi

TERRAFORM_VERSION=""
AWS_PROVIDER_VERSION=""
COMPANY=""
REPOSITORY_URL=""
AWS_PROFILE=""
AWS_REGION=""
PROJECT=""
# The ENVIRONMENTS can be a comma-separated list of environments,
# e.g. "production, staging, development", which will be used to create separate folders for each environment under the terraform folder.
# It will have the default value `production` if not provided.
ENVIRONMENTS="production"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --terraform-version)
      ensure_value "$1" "$#" "${2-}"
      TERRAFORM_VERSION="${2-}"
      shift 2
      ;;
    --aws-provider-version)
      ensure_value "$1" "$#" "${2-}"
      AWS_PROVIDER_VERSION="${2-}"
      shift 2
      ;;
    --company)
      ensure_value "$1" "$#" "${2-}"
      COMPANY="${2-}"
      shift 2
      ;;
    --repository-url)
      ensure_value "$1" "$#" "${2-}"
      REPOSITORY_URL="${2-}"
      shift 2
      ;;
    --aws-profile)
      ensure_value "$1" "$#" "${2-}"
      AWS_PROFILE="${2-}"
      shift 2
      ;;
    --aws-region)
      ensure_value "$1" "$#" "${2-}"
      AWS_REGION="${2-}"
      shift 2
      ;;
    --project)
      ensure_value "$1" "$#" "${2-}"
      PROJECT="${2-}"
      shift 2
      ;;
    --environments)
      ensure_value "$1" "$#" "${2-}"
      ENVIRONMENTS="${2-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

missing=()
[[ -z "$TERRAFORM_VERSION" ]] && missing+=("--terraform-version")
[[ -z "$AWS_PROVIDER_VERSION" ]] && missing+=("--aws-provider-version")
[[ -z "$COMPANY" ]] && missing+=("--company")
[[ -z "$REPOSITORY_URL" ]] && missing+=("--repository-url")
[[ -z "$AWS_PROFILE" ]] && missing+=("--aws-profile")
[[ -z "$AWS_REGION" ]] && missing+=("--aws-region")
[[ -z "$PROJECT" ]] && missing+=("--project")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Missing required arguments: ${missing[*]}" >&2
  usage
  exit 1
fi

TERRAFORM_REMOTE_STATE_S3_BUCKET="${COMPANY}-terraform-remote-state"

#-------------------- s3 bucket -------------------------------------------------------------------------#
# Check whether the S3 bucket for Terraform remote state exists or not. If it does not exist, create it. #

if ! aws s3 ls --profile "${AWS_PROFILE}" "s3://${TERRAFORM_REMOTE_STATE_S3_BUCKET}" > /dev/null 2>&1; then
  echo "Bucket ${TERRAFORM_REMOTE_STATE_S3_BUCKET} does not exist. Creating it..."
  aws s3 mb --profile "${AWS_PROFILE}" "s3://${TERRAFORM_REMOTE_STATE_S3_BUCKET}"
else
  echo "Bucket ${TERRAFORM_REMOTE_STATE_S3_BUCKET} already exists."
fi

#-------------------- terraform folder (non-environment specific) --------------------#
mkdir -p terraform
cd terraform

#------------------- .envrc --------------------#
echo "Preparing ${PWD}/.envrc file..."
export aws_profile=${AWS_PROFILE}
export aws_region=${AWS_REGION}
export company=${COMPANY}
export project=${PROJECT}
if [[ ! -f .envrc ]]; then
  envsubst < "${BOOTSTRAP_TERRAFORM_HOME_DIR}/.envrc.envsubst" > .envrc
fi

#-------------------- main.tf --------------------#
echo "Preparing ${PWD}/main.tf file..."
export aws_provider_version=${AWS_PROVIDER_VERSION}
export terraform_version=${TERRAFORM_VERSION}
if [[ ! -f main.tf ]]; then
  envsubst < "${BOOTSTRAP_TERRAFORM_HOME_DIR}/main.tf.envsubst" > main.tf
  terraform fmt -list=false main.tf
fi

#-------------------- providers.tf --------------------#
echo "Preparing ${PWD}/providers.tf file..."
export tf_repo=${REPOSITORY_URL}
if [[ ! -f providers.tf ]]; then
  envsubst < "${BOOTSTRAP_TERRAFORM_HOME_DIR}/providers.tf.envsubst" > providers.tf
  terraform fmt -list=false providers.tf
fi

#-------------------- variables.tf --------------------#
echo "Preparing ${PWD}/variables.tf file..."
if [[ ! -f variables.tf ]]; then
  envsubst < "${BOOTSTRAP_TERRAFORM_HOME_DIR}/variables.tf.envsubst" > variables.tf
  terraform fmt -list=false variables.tf
fi

#-------------------- environments --------------------#
IFS=',' read -ra environment_list <<< "${ENVIRONMENTS}"
for raw_environment in "${environment_list[@]}"; do
  environment="$(echo "${raw_environment}" | xargs)"
  [[ -z "${environment}" ]] && continue

  mkdir -p "${environment}"
  pushd "${environment}" > /dev/null

  echo "Preparing ${PWD}/.envrc file..."
  export environment="${environment}"
  if [[ ! -f .envrc ]]; then
    envsubst < "${BOOTSTRAP_TERRAFORM_HOME_DIR}/.envrc.environment.envsubst" > .envrc
  fi

  direnv allow

  echo "Preparing ${PWD}/backend.tf file..."
  export terraform_remote_state_s3_bucket_name="${TERRAFORM_REMOTE_STATE_S3_BUCKET}"
  if [[ ! -f backend.tf ]]; then
    envsubst < "${BOOTSTRAP_TERRAFORM_HOME_DIR}/backend.tf.envsubst" > backend.tf
    terraform fmt -list=false backend.tf
  fi

  echo "Creating symbolic link for main.tf"
  ln -sfn ../main.tf main.tf

  echo "Creating symbolic link for providers.tf"
  ln -sfn ../providers.tf providers.tf

  echo "Creating symbolic link for variables.tf"
  ln -sfn ../variables.tf variables.tf

  echo "Creating an empty terraform.tfvars file for environment-specific variable values"
  touch terraform.tfvars

  echo "Running terraform providers lock..."
  terraform providers lock --platform=linux_amd64 --platform=darwin_amd64 --platform=windows_amd64

  echo "Running terraform init..."
  terraform init

  popd > /dev/null
done

# TODO: amend the ".gitignore" file with ignore necessary for terraform.
# TODO: run terraform init for each environment to initialize the terraform working directory and download the necessary provider plugins.
# TODO: run the terraform providers ? for linux, macos and windows?
