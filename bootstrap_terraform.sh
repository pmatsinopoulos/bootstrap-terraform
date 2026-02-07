#!/usr/bin/env bash

set -e # e: exit if any command has a non-zero exit status
# set -x # x: all executed commands are printed to the terminal
set -u # u: all references to variables that have not been previously defined cause an error

BOOTSTRAP_TERRAFORM_HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TERRAFORM_VERSION=$1
AWS_PROVIDER_VERSION=$2
COMPANY=$3
REPOSITORY_URL=$4
AWS_PROFILE=$5
AWS_REGION=$6
PROJECT=$7
TERRAFORM_REMOTE_STATE_S3_BUCKET="${COMPANY}-terraform-remote-state"
# The ENVIRONMENTS can be a comma-separated list of environments,
# e.g. "production, staging, development", which will be used to create separate folders for each environment under the terraform folder.
# It will have the default value `production` if not provided.
ENVIRONMENTS=${8:-production}

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

  popd > /dev/null
done

# TODO: amend the ".gitignore" file with ignore necessary for terraform.
# TODO: run terraform init for each environment to initialize the terraform working directory and download the necessary provider plugins.
# TODO: run the terraform providers ? for linux, macos and windows?
