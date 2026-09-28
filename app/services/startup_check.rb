class StartupCheck
  Check = Data.define(:name, :message)

  class << self
    def run
      checks = []
      checks << check_data_path
      checks << check_compose_file
      checks << check_compose_project_name
      checks << check_env_file
      checks << check_data_writable

      if Rails.env.production?
        checks << check_docker_socket
        checks << check_docker_connection
        checks << check_docker_version
      end

      checks.compact
    end

    private

    def data_path
      Rails.configuration.data_path
    end

    def check_data_path
      return if File.directory?(data_path)

      Check.new(
        name: 'Data path',
        message:
          "Directory `#{data_path}` does not exist. " \
          "Add `- .:#{data_path}` to the volumes.",
      )
    end

    def check_compose_file
      return unless File.directory?(data_path)

      compose_exists =
        Compose::FILENAMES.any? do |filename|
          File.exist?(File.join(data_path, filename))
        end
      return if compose_exists

      Check.new(
        name: 'Compose file',
        message:
          "No compose file found in `#{data_path}`. " \
          "The volume should point to the directory containing #{Compose::FILENAMES.first}.",
      )
    end

    def check_compose_project_name
      return unless File.directory?(data_path)

      compose_file = existing_compose_file
      return unless compose_file

      name = (YAML.safe_load_file(compose_file) || {})['name']
      return if name == Orchestration::PROJECT_NAME

      Check.new(name: 'Compose project name', message: compose_project_name_message(compose_file, name))
    rescue Psych::SyntaxError => e
      Check.new(name: 'Compose project name', message: "Could not parse compose file: #{e.message}")
    end

    def existing_compose_file
      Compose::FILENAMES.map { |filename| File.join(data_path, filename) }.find { |path| File.exist?(path) }
    end

    def compose_project_name_message(compose_file, name)
      line = "`name: #{Orchestration::PROJECT_NAME}`"
      problem, fix =
        if name
          ["`#{compose_file}` sets the project name `#{name}`, but HELIOS requires " \
           "`#{Orchestration::PROJECT_NAME}`.", "change the line to #{line}"]
        else
          ["`#{compose_file}` has no top-level project name.", "add #{line} as the first line of the file"]
        end

      "#{problem} Stop the stack with `docker compose down`, #{fix}, " \
        'then start the stack with `docker compose up -d`.'
    end

    def check_env_file
      return unless File.directory?(data_path)
      return if File.exist?(File.join(data_path, '.env'))

      Check.new(
        name: 'Environment file',
        message:
          "No `.env` file found in `#{data_path}`. " \
          'The volume should point to the directory containing the .env file.',
      )
    end

    def check_data_writable
      return unless File.directory?(data_path)
      return if File.writable?(data_path)

      Check.new(
        name: 'Data path writable',
        message: "Directory `#{data_path}` is not writable.",
      )
    end

    def docker_socket
      Orchestration::Connection::SOCKET_PATHS.find { |path| File.exist?(path) }
    end

    def check_docker_socket
      return if docker_socket

      Check.new(
        name: 'Docker socket',
        message:
          'Docker socket not found. ' \
          'Add `- /var/run/docker.sock:/var/run/docker.sock` to the volumes.',
      )
    end

    def check_docker_connection
      return unless docker_socket

      Orchestration::Connection.configure!
      return if Docker.ping == 'OK'

      Check.new(
        name: 'Docker connection',
        message: 'Docker socket exists but connection failed.',
      )
    rescue StandardError => e
      Check.new(
        name: 'Docker connection',
        message: "Docker socket exists but connection failed: #{e.message}",
      )
    end

    def check_docker_version
      version = Orchestration::Connection.engine_version
      return if version.nil? # connection failure is reported by check_docker_connection
      return if version >= Orchestration::Connection::MIN_ENGINE_VERSION

      Check.new(
        name: 'Docker version',
        message:
          "Docker Engine #{version} is too old. " \
          "HELIOS requires #{Orchestration::Connection::MIN_ENGINE_VERSION} or newer.",
      )
    end
  end
end
