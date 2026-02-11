#!/usr/bin/env bash

set -e # e: exit if any command has a non-zero exit status
# set -x # x: all executed commands are printed to the terminal
set -u # u: all references to variables that have not been previously defined cause an error

BOOTSTRAP_DB_HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIRECTORY="${BOOTSTRAP_DB_HOME_DIR}/templates"
WORKING_DIR="$(pwd)"
# The ENVIRONMENTS can be a comma-separated list of environments,
# e.g. "production, staging, development", which will be used to create separate folders for each environment under the terraform folder.
# It will have the default value `production` if not provided.
ENVIRONMENTS="production"

missing_deps=()
for cmd in terraform envsubst direnv; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing_deps+=("$cmd")
  fi
done

if [[ ${#missing_deps[@]} -gt 0 ]]; then
  echo "Missing required commands: ${missing_deps[*]}" >&2
  echo "Please install the missing dependencies and retry." >&2
  exit 1
fi

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

usage() {
  cat <<'EOF'
Usage:
  bootstrap_terraform_db.sh \
    [--environments "production, staging, development"]

Required:

Optional:
  --environments    Comma-separated list (default: "production")
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

# missing=()
# [[ -z "$TERRAFORM_VERSION" ]] && missing+=("--terraform-version")
# [[ -z "$AWS_PROVIDER_VERSION" ]] && missing+=("--aws-provider-version")
# [[ -z "$COMPANY" ]] && missing+=("--company")
# [[ -z "$REPOSITORY_URL" ]] && missing+=("--repository-url")
# [[ -z "$AWS_PROFILE" ]] && missing+=("--aws-profile")
# [[ -z "$AWS_REGION" ]] && missing+=("--aws-region")
# [[ -z "$PROJECT" ]] && missing+=("--project")

# if [[ ${#missing[@]} -gt 0 ]]; then
#   echo "Missing required arguments: ${missing[*]}" >&2
#   usage
#   exit 1
# fi

pushd terraform > /dev/null

#-------------------- db_subnet_group.tf --------------------#
echo "Preparing ${PWD}/db_subnet_group.tf file..."
if [[ ! -f db_subnet_group.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/db_subnet_group.tf.envsubst" > db_subnet_group.tf
  terraform fmt -list=false db_subnet_group.tf
fi

#-------------------- db_security_group.tf --------------------#
echo "Preparing ${PWD}/db_security_group.tf file..."
if [[ ! -f db_security_group.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/db_security_group.tf.envsubst" > db_security_group.tf
  terraform fmt -list=false db_security_group.tf
fi

#-------------------- db.tf --------------------#
echo "Preparing ${PWD}/db.tf file..."
if [[ ! -f db.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/db.tf.envsubst" > db.tf
  terraform fmt -list=false db.tf
fi

#-------------------- db_instance_enhanced_monitoring_role.tf --------------------#
echo "Preparing ${PWD}/db_instance_enhanced_monitoring_role.tf file..."
if [[ ! -f db_instance_enhanced_monitoring_role.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/db_instance_enhanced_monitoring_role.tf.envsubst" > db_instance_enhanced_monitoring_role.tf
  terraform fmt -list=false db_instance_enhanced_monitoring_role.tf
fi

#-------------------- db_migrations.tf --------------------#
echo "Preparing ${PWD}/db_migrations.tf file..."
if [[ ! -f db_migrations.tf ]]; then
  envsubst '' < "${TEMPLATES_DIRECTORY}/db_migrations.tf.envsubst" > db_migrations.tf
  terraform fmt -list=false db_migrations.tf
fi

#-------------------- environments --------------------#
IFS=',' read -ra environment_list <<< "${ENVIRONMENTS}"
for raw_environment in "${environment_list[@]}"; do
  environment="$(echo "${raw_environment}" | xargs)"
  [[ -z "${environment}" ]] && continue

  pushd "${environment}" > /dev/null

  echo "Creating symbolic link for db_subnet_group.tf"
  ln -sfn ../db_subnet_group.tf db_subnet_group.tf

  echo "Creating symbolic link for db_security_group.tf"
  ln -sfn ../db_security_group.tf db_security_group.tf

  echo "Creating symbolic link for db_instance_enhanced_monitoring_role.tf"
  ln -sfn ../db_instance_enhanced_monitoring_role.tf db_instance_enhanced_monitoring_role.tf

  echo "Creating symbolic link for db.tf"
  ln -sfn ../db.tf db.tf

  echo "Creating symbolic link for db_migrations.tf"
  ln -sfn ../db_migrations.tf db_migrations.tf

  popd > /dev/null
done

popd > /dev/null
