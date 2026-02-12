I use scripts to add _terraform_ code in any **existing** repository. This makes me bootstrap
terraform code faster.

# Installation

Clone this repository.

Add the root folder of this repository to your $PATH environment variable
so that you can call it from any other folder/repository you want to use it for.

# Pre-requisites

- Works with AWS
- AWS cli needs to be installed
- AWS_PROFILE needs to be configured with all the necessary privileges to create an S3 bucket to store the state remotely.
- [direnv](https://direnv.net/)
- [terraform](https://developer.hashicorp.com/terraform/install)
- `envsubst`

# Usage

Example call from a repository named `my-fantastic-web-app`:

## For `production` Environment

```bash
bootstrap_terraform.sh \
  --terraform-version 1.14.4 \
  --aws-provider-version 6.31.0 \
  --company pmatsinopoulos \
  --repository-url 'https://github.com/pmatsinopoulos/my-fantastic-web-app' \
  --aws-profile 'aws-profile-default' \
  --aws-region eu-west-1 \
  --project my-fantastic-web-app \
  --ruby-version 3.4.8 \
  --domain-name 'foo.matsinopoulos.gr' \
  --nodejs-version 20
```

## For `staging` environment:

```bash
bootstrap_terraform.sh \
  --terraform-version 1.14.4 \
  --aws-provider-version 6.31.0 \
  --company pmatsinopoulos \
  --repository-url 'https://github.com/pmatsinopoulos/my-fantastic-web-app' \
  --aws-profile 'aws-profile-default' \
  --aws-region eu-west-1 \
  --project my-fantastic-web-app \
  --ruby-version 3.4.8 \
  --nodejs-version 20 \
  --domain-name 'foo.matsinopoulos.gr' \
  --environments staging
```

## For many environments at once:

```bash
bootstrap_terraform.sh \
  --terraform-version 1.14.4 \
  --aws-provider-version 6.31.0 \
  --company pmatsinopoulos \
  --repository-url 'https://github.com/pmatsinopoulos/my-fantastic-web-app' \
  --aws-profile 'aws-profile-default' \
  --aws-region eu-west-1 \
  --project my-fantastic-web-app \
  --ruby-version 3.4.8 \
  --nodejs-version 20 \
  --domain-name 'foo.matsinopoulos.gr' \
  --environments 'production,staging'
```

## Notes

You can run the script multiple times. It will not do anything if the files already exist.
