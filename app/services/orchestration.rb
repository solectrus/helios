require 'docker-api'

module Orchestration
  class ConnectionError < StandardError
  end

  COMPOSE_PROJECT_LABEL = 'com.docker.compose.project'.freeze
  COMPOSE_SERVICE_LABEL = 'com.docker.compose.service'.freeze
  COMPOSE_CONFIG_HASH_LABEL = 'com.docker.compose.config-hash'.freeze

  class << self
    delegate :configure!, :connected?, to: 'Orchestration::Connection'

    def default_project
      ENV.fetch('COMPOSE_PROJECT_NAME', nil) || project_from_data_path
    end

    private

    def project_from_data_path
      data_path = Rails.configuration.data_path
      return nil unless data_path

      compose_file = ::File.join(data_path, 'compose.yaml')
      return ::File.basename(data_path) unless ::File.exist?(compose_file)

      config = YAML.safe_load_file(compose_file)
      config['name'] || ::File.basename(data_path)
    end
  end
end
