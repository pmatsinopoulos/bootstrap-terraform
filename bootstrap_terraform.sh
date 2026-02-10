#!/usr/bin/env bash

set -e # e: exit if any command has a non-zero exit status
# set -x # x: all executed commands are printed to the terminal
set -u # u: all references to variables that have not been previously defined cause an error

BOOTSTRAP_TERRAFORM_HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIRECTORY="${BOOTSTRAP_TERRAFORM_HOME_DIR}/templates"
WORKING_DIR="$(pwd)"

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

ensure_terraform_gitignore() {
  local working_dir="${1-}"
  local gitignore_path="${working_dir}/.gitignore"
  if [[ ! -f "${gitignore_path}" ]]; then
    return 0
  fi

  local terraform_gitignore_lines
  terraform_gitignore_lines=(
    "# Terraform"
    "**/.terraform/"
    "**/*.tfstate"
    "**/*.tfstate.*"
    "**/crash.log"
    "**/crash.*.log"
    "**/*.tfplan"
  )

  local terraform_gitignore_line
  local appended_any=false
  for terraform_gitignore_line in "${terraform_gitignore_lines[@]}"; do
    if ! grep -Fxq "${terraform_gitignore_line}" "${gitignore_path}"; then
      echo "${terraform_gitignore_line}" >> "${gitignore_path}"
      appended_any=true
    fi
  done

  if [[ "${appended_any}" == true ]] && [[ -n "$(tail -n 1 "${gitignore_path}")" ]]; then
    printf '\n' >> "${gitignore_path}"
  fi
}

missing_deps=()
for cmd in aws terraform envsubst direnv; do
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
    --ruby-version)
      ensure_value "$1" "$#" "${2-}"
      RUBY_VERSION="${2-}"
      shift 2
      ;;
    --nodejs-version)
      ensure_value "$1" "$#" "${2-}"
      NODEJS_VERSION="${2-}"
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
[[ -z "$RUBY_VERSION" ]] && missing+=("--ruby-version")
[[ -z "$NODEJS_VERSION" ]] && missing+=("--nodejs-version")

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
pushd terraform > /dev/null

#------------------- .envrc --------------------#
echo "Preparing ${PWD}/.envrc file..."
export aws_profile=${AWS_PROFILE}
export aws_region=${AWS_REGION}
export company=${COMPANY}
export project=${PROJECT}
if [[ ! -f .envrc ]]; then
  envsubst '$aws_profile $aws_region $company $project' < "${TEMPLATES_DIRECTORY}/.envrc.envsubst" > .envrc
fi
direnv allow .
eval "$(direnv export bash)"

#-------------------- main.tf --------------------#
echo "Preparing ${PWD}/main.tf file..."
export aws_provider_version=${AWS_PROVIDER_VERSION}
export terraform_version=${TERRAFORM_VERSION}
if [[ ! -f main.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/main.tf.envsubst" > main.tf
  terraform fmt -list=false main.tf
fi

#-------------------- providers.tf --------------------#
echo "Preparing ${PWD}/providers.tf file..."
export tf_repo=${REPOSITORY_URL}
if [[ ! -f providers.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/providers.tf.envsubst" > providers.tf
  terraform fmt -list=false providers.tf
fi

#-------------------- variables.tf --------------------#
echo "Preparing ${PWD}/variables.tf file..."
if [[ ! -f variables.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/variables.tf.envsubst" > variables.tf
  terraform fmt -list=false variables.tf
fi

#-------------------- locals.tf --------------------#
echo "Preparing ${PWD}/locals.tf file..."
if [[ ! -f locals.tf ]]; then
  envsubst '' < "${TEMPLATES_DIRECTORY}/locals.tf.envsubst" > locals.tf
  terraform fmt -list=false locals.tf
fi

#-------------------- data.tf --------------------#
echo "Preparing ${PWD}/data.tf file..."
if [[ ! -f data.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/data.tf.envsubst" > data.tf
  terraform fmt -list=false data.tf
fi

#-------------------- environments --------------------#
IFS=',' read -ra environment_list <<< "${ENVIRONMENTS}"
for raw_environment in "${environment_list[@]}"; do
  environment="$(echo "${raw_environment}" | xargs)"
  [[ -z "${environment}" ]] && continue

  echo "*************************************** Environment: ${environment} ***************************************"

  mkdir -p "${environment}"
  pushd "${environment}" > /dev/null

  echo "Preparing ${PWD}/.envrc file..."
  export environment="${environment}"
  if [[ ! -f .envrc ]]; then
    envsubst < "${TEMPLATES_DIRECTORY}/.envrc.environment.envsubst" > .envrc
  fi

  direnv allow .
  eval "$(direnv export bash)"

  echo "Preparing ${PWD}/backend.tf file..."
  export terraform_remote_state_s3_bucket_name="${TERRAFORM_REMOTE_STATE_S3_BUCKET}"
  if [[ ! -f backend.tf ]]; then
    envsubst < "${TEMPLATES_DIRECTORY}/backend.tf.envsubst" > backend.tf
    terraform fmt -list=false backend.tf
  fi

  echo "Creating symbolic link for main.tf"
  ln -sfn ../main.tf main.tf

  echo "Creating symbolic link for providers.tf"
  ln -sfn ../providers.tf providers.tf

  echo "Creating symbolic link for variables.tf"
  ln -sfn ../variables.tf variables.tf

  echo "Creating symbolic link for locals.tf"
  ln -sfn ../locals.tf locals.tf

  echo "Creating symbolic link for data.tf"
  ln -sfn ../data.tf data.tf

  #-------------------- terraform.tfvars --------------------#
  echo "Preparing ${PWD}/terraform.tfvars file..."
  if [[ ! -f terraform.tfvars ]]; then
    envsubst < "${TEMPLATES_DIRECTORY}/terraform.tfvars.envsubst" > terraform.tfvars
    terraform fmt -list=false terraform.tfvars
  fi

  echo "Running terraform providers lock..."
  terraform providers lock --platform=linux_amd64 --platform=darwin_amd64 --platform=windows_amd64

  echo "Current AWS-related environment variables:"
  printenv | grep 'AWS' || true

  echo "Running terraform init..."
  terraform init

  popd > /dev/null
done

ensure_terraform_gitignore "${WORKING_DIR}"

popd > /dev/null

#-------------------- Network ---------------------#

echo "********************* Network Bootstrap *********************"

bootstrap_terraform_network.sh --environments "${ENVIRONMENTS}"

#-------------------- DB RDS Postgres ---------------------#

echo "********************* DB RDS Postgres Bootstrap *********************"

bootstrap_terraform_db.sh --environments "${ENVIRONMENTS}"

#-------------------- Build and push image ---------------------#

echo "********************* Build and Push Image Bootstrap *********************"

bootstrap_terraform_build_and_push_image.sh --environments "${ENVIRONMENTS}" --ruby-version "${RUBY_VERSION}" --nodejs-version "${NODEJS_VERSION}"
