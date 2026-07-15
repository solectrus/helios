# syntax=docker/dockerfile:1
# check=error=true

# Skip the builder's Bootsnap precompile: a ~45 MB cache, regenerated at runtime.
ARG SKIP_BOOTSNAP_PRECOMPILE=1

FROM ghcr.io/ledermann/rails-base-builder:4.0.6-alpine AS builder

# Remove some files not needed in resulting image.
# Because they are required for building the image, they can't be added to .dockerignore
RUN rm -r package.json vite.config.mts tsconfig.json

FROM ghcr.io/ledermann/rails-base-final:4.0.6-alpine
LABEL maintainer="georg@ledermann.dev"
LABEL org.opencontainers.image.description="HELIOS — knows your SOLECTRUS configuration better than you do"

# Install Docker CLI for managing compose stacks
RUN apk add --no-cache docker-cli docker-cli-compose

# Run as root to access the Docker socket and manage containers on the host
USER root

# Enable YJIT
ENV RUBY_YJIT_ENABLE=1

# Entrypoint prepares the database.
ENTRYPOINT ["docker/entrypoint.sh"]

# Start the server by default, this can be overwritten at runtime
CMD ["./bin/rails", "server"]
