require 'docker-api'

module Orchestration
  class ConnectionError < StandardError
  end

  # Docker Compose container labels used to identify and filter containers
  # belonging to this stack. See: https://docs.docker.com/reference/compose-file/merge/
  COMPOSE_PROJECT_LABEL = 'com.docker.compose.project'.freeze
  COMPOSE_SERVICE_LABEL = 'com.docker.compose.service'.freeze
  COMPOSE_CONFIG_HASH_LABEL = 'com.docker.compose.config-hash'.freeze

  # The Docker Compose project name is always "solectrus". This matches the
  # name written by Helios when generating compose.yaml (see Export::Compose)
  # and is enforced on startup by StartupCheck#check_compose_project_name.
  PROJECT_NAME = 'solectrus'.freeze
end
