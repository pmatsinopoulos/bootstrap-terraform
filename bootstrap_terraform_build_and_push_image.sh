#!/usr/bin/env bash

set -e # e: exit if any command has a non-zero exit status
# set -x # x: all executed commands are printed to the terminal
set -u # u: all references to variables that have not been previously defined cause an error

BOOTSTRAP_IMAGE_HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIRECTORY="${BOOTSTRAP_IMAGE_HOME_DIR}/templates"
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
[[ -z "$RUBY_VERSION" ]] && missing+=("--ruby-version")
[[ -z "$NODEJS_VERSION" ]] && missing+=("--nodejs-version")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Missing required arguments: ${missing[*]}" >&2
  usage
  exit 1
fi

cp "${TEMPLATES_DIRECTORY}/build_image.sh" "${PWD}/build_image.sh"
chmod +x "${PWD}/build_image.sh"

#-------------------- ecs.main.Dockerfile.dockerignore --------------------#
echo "Preparing ${PWD}/ecs.main.Dockerfile.dockerignore file..."

if [[ ! -f ecs.main.Dockerfile.dockerignore ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/ecs.main.Dockerfile.dockerignore.envsubst" > ecs.main.Dockerfile.dockerignore
fi

#-------------------- ecs.main.Dockerfile --------------------#
echo "Preparing ${PWD}/ecs.main.Dockerfile file..."

if [[ ! -f ecs.main.Dockerfile ]]; then
  export ruby_version=${RUBY_VERSION}
  export nodejs_version=${NODEJS_VERSION}
  envsubst '$ruby_version $nodejs_version'< "${TEMPLATES_DIRECTORY}/ecs.main.Dockerfile.envsubst" > ecs.main.Dockerfile
fi

#-------------------- cd.container_runner.Dockerfile.dockerignore --------------------#
echo "Preparing ${PWD}/cd.container_runner.Dockerfile.dockerignore file..."

if [[ ! -f cd.container_runner.Dockerfile.dockerignore ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/cd.container_runner.Dockerfile.dockerignore.envsubst" > cd.container_runner.Dockerfile.dockerignore
fi

#-------------------- cd.container_runner.Dockerfile --------------------#
echo "Preparing ${PWD}/cd.container_runner.Dockerfile file..."

if [[ ! -f cd.container_runner.Dockerfile ]]; then
  export ruby_version=${RUBY_VERSION}
  export nodejs_version=${NODEJS_VERSION}
  envsubst '$ruby_version $nodejs_version'< "${TEMPLATES_DIRECTORY}/cd.container_runner.Dockerfile.envsubst" > cd.container_runner.Dockerfile
fi

pushd terraform > /dev/null

eval "$(direnv export bash)"

#-------------------- ecr.tf --------------------#
echo "Preparing ${PWD}/ecr.tf file..."

if [[ ! -f ecr.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/ecr.tf.envsubst" > ecr.tf
  terraform fmt -list=false ecr.tf
fi

#-------------------- ecr_build_image.tf --------------------#
echo "Preparing ${PWD}/ecr_build_image.tf file..."

if [[ ! -f ecr_build_image.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/ecr_build_image.tf.envsubst" > ecr_build_image.tf
  terraform fmt -list=false ecr_build_image.tf
fi

#-------------------- environments --------------------#
IFS=',' read -ra environment_list <<< "${ENVIRONMENTS}"
for raw_environment in "${environment_list[@]}"; do
  environment="$(echo "${raw_environment}" | xargs)"
  [[ -z "${environment}" ]] && continue

  echo "*************************************** Environment: ${environment} ***************************************"

  pushd "${environment}" > /dev/null

  eval "$(direnv export bash)"

  echo "Creating symbolic link for ecr.tf"
  ln -sfn ../ecr.tf ecr.tf

  echo "Creating symbolic link for ecr_build_image.tf"
  ln -sfn ../ecr_build_image.tf ecr_build_image.tf

  popd > /dev/null
done

popd > /dev/null
