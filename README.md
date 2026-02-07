I use this script to add _terraform_ code in any **existing** repository.

# Installation

Clone this repository.

Add the root folder of this repository to your $PATH environment variable
so that you can call it from any other folder/repository you want to use it for.

# Usage

Example call from a repository named `my-fantastic-web-app`:

## For `production` Environment

```bash
bootstrap_terraform.sh 1.14.4 6.31.0 pmatsinopoulos 'https://github.com/pmatsinopoulos/my-fantastic-web-app' 'aws-profile-default' eu-west-1 my-fantastic-web-app
```

## For `staging` environment:

```bash
bootstrap_terraform.sh 1.14.4 6.31.0 pmatsinopoulos 'https://github.com/pmatsinopoulos/my-fantastic-web-app' 'aws-profile-default' eu-west-1 my-fantastic-web-app staging
```

## For many environments at once:

```bash
bootstrap_terraform.sh 1.14.4 6.31.0 pmatsinopoulos 'https://github.com/pmatsinopoulos/my-fantastic-web-app' 'aws-profile-default' eu-west-1 my-fantastic-web-app 'production,staging'
```

## Notes

You can run the script multiple times. It will not do anything if the files already exist.
