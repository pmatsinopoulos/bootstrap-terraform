#!/usr/bin/env bash

set -e # e: exit if any command has a non-zero exit status
# set -x # x: all executed commands are printed to the terminal
set -u # u: all references to variables that have not been previously defined cause an error

BOOTSTRAP_ECS_HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIRECTORY="${BOOTSTRAP_ECS_HOME_DIR}/templates"
WORKING_DIR="$(pwd)"
ENVIRONMENTS="production"
DOMAIN_NAME=""

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
    --domain-name "example.com" \
    [--environments "production, staging, development"]

Required:
  --domain-name     The domain name for the application, e.g. "example.com"

Optional:
  --environments    Comma-separated list (default: "production")
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain-name)
      ensure_value "$1" "$#" "${2-}"
      DOMAIN_NAME="${2-}"
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
[[ -z "$DOMAIN_NAME" ]] && missing+=("--domain-name")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Missing required arguments: ${missing[*]}" >&2
  usage
  exit 1
fi

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

#-------------------- server_ecs_task_definition.tf --------------------#
echo "Preparing ${PWD}/server_ecs_task_definition.tf file..."

if [[ ! -f server_ecs_task_definition.tf ]]; then
  envsubst '' < "${TEMPLATES_DIRECTORY}/server_ecs_task_definition.tf.envsubst" > server_ecs_task_definition.tf
  terraform fmt -list=false server_ecs_task_definition.tf
fi

#-------------------- server_cluster_service.tf --------------------#
echo "Preparing ${PWD}/server_cluster_service.tf file..."

if [[ ! -f server_cluster_service.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/server_cluster_service.tf.envsubst" > server_cluster_service.tf
  terraform fmt -list=false server_cluster_service.tf
fi

#-------------------- ecs_task_execution_role.tf --------------------#
echo "Preparing ${PWD}/ecs_task_execution_role.tf file..."

if [[ ! -f ecs_task_execution_role.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/ecs_task_execution_role.tf.envsubst" > ecs_task_execution_role.tf
  terraform fmt -list=false ecs_task_execution_role.tf
fi

#-------------------- ecs_task_role.tf --------------------#
echo "Preparing ${PWD}/ecs_task_role.tf file..."

if [[ ! -f ecs_task_role.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/ecs_task_role.tf.envsubst" > ecs_task_role.tf
  terraform fmt -list=false ecs_task_role.tf
fi

#-------------------- server_cloudwatch_log_group.tf --------------------#
echo "Preparing ${PWD}/server_cloudwatch_log_group.tf file..."

if [[ ! -f server_cloudwatch_log_group.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/server_cloudwatch_log_group.tf.envsubst" > server_cloudwatch_log_group.tf
  terraform fmt -list=false server_cloudwatch_log_group.tf
fi

#-------------------- server_load_balancer_logs_s3_bucket.tf --------------------#
echo "Preparing ${PWD}/server_load_balancer_logs_s3_bucket.tf file..."

if [[ ! -f server_load_balancer_logs_s3_bucket.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/server_load_balancer_logs_s3_bucket.tf.envsubst" > server_load_balancer_logs_s3_bucket.tf
  terraform fmt -list=false server_load_balancer_logs_s3_bucket.tf
fi

#-------------------- server_load_balancer_security_groups.tf --------------------#
echo "Preparing ${PWD}/server_load_balancer_security_groups.tf file..."

if [[ ! -f server_load_balancer_security_groups.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/server_load_balancer_security_groups.tf.envsubst" > server_load_balancer_security_groups.tf
  terraform fmt -list=false server_load_balancer_security_groups.tf
fi

#-------------------- server_load_balancer.tf --------------------#
echo "Preparing ${PWD}/server_load_balancer.tf file..."

if [[ ! -f server_load_balancer.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/server_load_balancer.tf.envsubst" > server_load_balancer.tf
  terraform fmt -list=false server_load_balancer.tf
fi

#-------------------- ssl_certificate.tf --------------------#
echo "Preparing ${PWD}/ssl_certificate.tf file..."

if [[ ! -f ssl_certificate.tf ]]; then
  export domain_name="${DOMAIN_NAME}"
  envsubst < "${TEMPLATES_DIRECTORY}/ssl_certificate.tf.envsubst" > ssl_certificate.tf
  terraform fmt -list=false ssl_certificate.tf
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

  echo "Creating symbolic link for server_ecs_task_definition.tf"
  ln -sfn ../server_ecs_task_definition.tf server_ecs_task_definition.tf

  echo "Creating symbolic link for server_cluster_service.tf"
  ln -sfn ../server_cluster_service.tf server_cluster_service.tf

  echo "Creating symbolic link for ecs_task_execution_role.tf"
  ln -sfn ../ecs_task_execution_role.tf ecs_task_execution_role.tf

  echo "Creating symbolic link for ecs_task_role.tf"
  ln -sfn ../ecs_task_role.tf ecs_task_role.tf

  echo "Creating symbolic link for server_cloudwatch_log_group.tf"
  ln -sfn ../server_cloudwatch_log_group.tf server_cloudwatch_log_group.tf

  echo "Creating symbolic link for server_load_balancer_logs_s3_bucket.tf"
  ln -sfn ../server_load_balancer_logs_s3_bucket.tf server_load_balancer_logs_s3_bucket.tf

  echo "Creating symbolic link for server_load_balancer_security_groups.tf"
  ln -sfn ../server_load_balancer_security_groups.tf server_load_balancer_security_groups.tf

  echo "Creating symbolic link for server_load_balancer.tf"
  ln -sfn ../server_load_balancer.tf server_load_balancer.tf

  echo "Creating symbolic link for ssl_certificate.tf"
  ln -sfn ../ssl_certificate.tf ssl_certificate.tf

  popd > /dev/null
done

popd > /dev/null
