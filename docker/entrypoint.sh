#!/bin/sh -e
echo "HELIOS - Knows all about your SOLECTRUS instance"
echo "Version ${COMMIT_VERSION}, built on ${COMMIT_TIME}"
echo "Using $(ruby -v)"
echo "Based on Alpine Linux $(cat /etc/alpine-release)"

echo ""
echo "Copyright (C) 2020-2026 Georg Ledermann. All rights reserved."

# If running the rails server then wait for services
# and create or migrate existing database
if [ "${1}" == "./bin/rails" ] && [ "${2}" == "server" ]; then
  # Create or migrate database
  echo ""
  echo "## Preparing database..."
  ./bin/rails db:prepare
  echo "Database is ready!"

  echo ""
  echo "## Starting Rails application..."
fi

exec "${@}"
