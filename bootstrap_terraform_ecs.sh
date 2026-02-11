#!/usr/bin/env bash

set -e # e: exit if any command has a non-zero exit status
# set -x # x: all executed commands are printed to the terminal
set -u # u: all references to variables that have not been previously defined cause an error

BOOTSTRAP_ECS_HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIRECTORY="${BOOTSTRAP_ECS_HOME_DIR}/templates"
WORKING_DIR="$(pwd)"
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
  bootstrap_terraform_build_and_push_image.sh \
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
# [[ -z "$RUBY_VERSION" ]] && missing+=("--ruby-version")
# [[ -z "$NODEJS_VERSION" ]] && missing+=("--nodejs-version")

# if [[ ${#missing[@]} -gt 0 ]]; then
#   echo "Missing required arguments: ${missing[*]}" >&2
#   usage
#   exit 1
# fi

pushd terraform > /dev/null

eval "$(direnv export bash)"

#-------------------- ecs_cluster.tf --------------------#
echo "Preparing ${PWD}/ecs_cluster.tf file..."

if [[ ! -f ecs_cluster.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/ecs_cluster.tf.envsubst" > ecs_cluster.tf
  terraform fmt -list=false ecs_cluster.tf
fi

#-------------------- environment.tf --------------------#
echo "Preparing ${PWD}/environment.tf file..."

if [[ ! -f environment.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/environment.tf.envsubst" > environment.tf
  terraform fmt -list=false environment.tf
fi

#-------------------- environments --------------------#
IFS=',' read -ra environment_list <<< "${ENVIRONMENTS}"
for raw_environment in "${environment_list[@]}"; do
  environment="$(echo "${raw_environment}" | xargs)"
  [[ -z "${environment}" ]] && continue

  echo "*************************************** Environment: ${environment} ***************************************"

  pushd "${environment}" > /dev/null

  eval "$(direnv export bash)"

  echo "Creating symbolic link for ecs_cluster.tf"
  ln -sfn ../ecs_cluster.tf ecs_cluster.tf

  echo "Creating symbolic link for environment.tf"
  ln -sfn ../environment.tf environment.tf

  popd > /dev/null
done

popd > /dev/null
