#!/usr/bin/env bash

set -e # e: exit if any command has a non-zero exit status
set -x # x: all executed commands are printed to the terminal
set -u # u: all references to variables that have not been previously defined cause an error

tag=$1
dockerfile=$2
environment=$3

YARN_CACHE_FOLDER=$(pwd)/vendor/yarncache

BUNDLE_CACHE_ALL=true
BUNDLE_CACHE_ALL_PLATFORMS=true
BUNDLE_CACHE_PATH='vendor/cache'
BUNDLE_PATH='vendor/bundle'

if [ -n "${CI:-}" ]; then
  echo "We are running in CI. Hence, we will not yarn neither bundle"
else
  echo "We are not running in CI. Hence, we will yarn and bundle"

  rm -f -R tmp/cache/assets
  rm -f -R public/assets
  rm -f -R public/packs

  yarn install --frozen-lockfile --non-interactive --cache-folder "${YARN_CACHE_FOLDER}"

  echo '....ready to bundle install'

  bundle cache --no-install
  bundle install

  bundle exec dotenv -f ".env.${environment}" rake assets:clobber
  bundle exec dotenv -f ".env.${environment}" rake assets:precompile
fi

docker build --file "${dockerfile}" --tag "${tag}" .

if [ -n "${CI:-}" ]; then
  echo "We are running in CI. Hence, we will not delete the temporary files"
else
  echo "We are not running in CI. Hence, we will delete the temporary files"
  rm -f -R tmp/cache/assets
  rm -f -R public/assets
  rm -f -R public/packs
fi
