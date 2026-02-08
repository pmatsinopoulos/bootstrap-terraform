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
  bootstrap_terraform_network.sh \
    [--environments "production, staging, development"]

Required:

Optional:
  --environments    Comma-separated list (default: "production")
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
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
# [[ -z "$VPC_CIDR_BLOCK" ]] && missing+=("--vpc-cidr-block")
# [[ -z "$SUBNET_1_CIDR_BLOCK" ]] && missing+=("--subnet-1-cidr-block")
# [[ -z "$SUBNET_2_CIDR_BLOCK" ]] && missing+=("--subnet-2-cidr-block")
# [[ -z "$SUBNET_3_CIDR_BLOCK" ]] && missing+=("--subnet-3-cidr-block")

# if [[ ${#missing[@]} -gt 0 ]]; then
#   echo "Missing required arguments: ${missing[*]}" >&2
#   usage
#   exit 1
# fi

cd terraform

#-------------------- access_to_internet.tf --------------------#
echo "Preparing ${PWD}/access_to_internet.tf file..."

if [[ ! -f access_to_internet.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/access_to_internet.tf.envsubst" > access_to_internet.tf
  terraform fmt -list=false access_to_internet.tf
fi

#-------------------- internet_gateway.tf --------------------#
echo "Preparing ${PWD}/internet_gateway.tf file..."

if [[ ! -f internet_gateway.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/internet_gateway.tf.envsubst" > internet_gateway.tf
  terraform fmt -list=false internet_gateway.tf
fi

#-------------------- route_table.tf --------------------#
echo "Preparing ${PWD}/route_table.tf file..."

if [[ ! -f route_table.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/route_table.tf.envsubst" > route_table.tf
  terraform fmt -list=false route_table.tf
fi

#-------------------- vpc_subnets.tf --------------------#
echo "Preparing ${PWD}/vpc_subnets.tf file..."

if [[ ! -f vpc_subnets.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/vpc_subnets.tf.envsubst" > vpc_subnets.tf
  terraform fmt -list=false vpc_subnets.tf
fi

#-------------------- vpc.tf --------------------#
echo "Preparing ${PWD}/vpc.tf file..."

if [[ ! -f vpc.tf ]]; then
  envsubst < "${TEMPLATES_DIRECTORY}/vpc.tf.envsubst" > vpc.tf
  terraform fmt -list=false vpc.tf
fi

#-------------------- environments --------------------#
IFS=',' read -ra environment_list <<< "${ENVIRONMENTS}"
for raw_environment in "${environment_list[@]}"; do
  environment="$(echo "${raw_environment}" | xargs)"
  [[ -z "${environment}" ]] && continue

  pushd "${environment}" > /dev/null

  echo "Creating symbolic link for access_to_internet.tf"
  ln -sfn ../access_to_internet.tf access_to_internet.tf

  echo "Creating symbolic link for internet_gateway.tf"
  ln -sfn ../internet_gateway.tf internet_gateway.tf

  echo "Creating symbolic link for route_table.tf"
  ln -sfn ../route_table.tf route_table.tf

  echo "Creating symbolic link for vpc_subnets.tf"
  ln -sfn ../vpc_subnets.tf vpc_subnets.tf

  echo "Creating symbolic link for vpc.tf"
  ln -sfn ../vpc.tf vpc.tf

  popd > /dev/null
done
