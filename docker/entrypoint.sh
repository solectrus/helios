#!/bin/sh -e

# The base image writes the Git metadata to this file. The env vars of the same
# name can hold the values of an older image (see lib/build_info.rb).
version=$(sed -n 's/^COMMIT_VERSION=//p' /etc/build-info)
built=$(sed -n 's/^COMMIT_TIME=//p' /etc/build-info)

echo "HELIOS — knows your SOLECTRUS configuration better than you do"
echo "Version ${version}, built on ${built}"
echo "Using $(ruby -v)"
echo "Based on Alpine Linux $(cat /etc/alpine-release)"

echo ""
echo "Copyright (C) 2020-2026 Georg Ledermann. All rights reserved."

# If running the rails server then wait for services
# and create or migrate existing database
if [ "${1}" = "./bin/rails" ] && [ "${2}" = "server" ]; then
  # Create or migrate database
  echo ""
  echo "## Preparing database..."
  ./bin/rails db:prepare
  echo "Database is ready!"

  echo ""
  echo "## Starting Rails application..."
fi

exec "${@}"
