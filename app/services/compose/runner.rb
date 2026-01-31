require 'open3'

module Compose
  class Runner
    class CommandError < StandardError
      attr_reader :stdout, :stderr, :exit_status

      def initialize(message, stdout: '', stderr: '', exit_status: nil)
        super(message)
        @stdout = stdout
        @stderr = stderr
        @exit_status = exit_status
      end
    end

    class << self
      SELF_SERVICE = 'helios'.freeze

      def up(detach: true)
        args = %w[up --no-build]
        args << '-d' if detach
        # Exclude self to avoid restarting Helios during up
        args.concat(services_except_self)
        run_compose(*args)
      end

      def down(remove_volumes: false)
        args = ['down']
        args << '-v' if remove_volumes
        run_compose(*args)
      end

      def pull(service: nil)
        args = ['pull']
        args << service if service
        run_compose(*args)
      end

      def restart(service = nil)
        args = ['restart']
        args << service if service
        run_compose(*args)
      end

      def start(*services)
        # Use 'up -d' instead of 'start' to also create containers if they don't exist
        args = %w[up --no-build -d]
        args.concat(services.flatten.compact)
        run_compose(*args)
      end

      def stop(service = nil)
        args = ['stop']
        args << service if service
        run_compose(*args)
      end

      def logs(service: nil, tail: nil, follow: false)
        args = ['logs']
        args << '-f' if follow
        args += ['--tail', tail.to_s] if tail
        args << service if service
        run_compose(*args)
      end

      def ps
        run_compose('ps')
      end

      def stack_path
        Rails.configuration.helios_stack_path
      end

      def host_stack_path
        Rails.configuration.helios_host_stack_path
      end

      private

      def run_compose(*args)
        validate_stack_path!

        cmd = [
          'docker',
          'compose',
          '-f',
          Compose.path,
          '--project-directory',
          host_stack_path,
          '--progress',
          'plain',
          *args.map(&:to_s),
        ]

        output, status = Open3.capture2e(*cmd)

        unless status.success?
          raise CommandError.new(
                  "docker compose #{args.first} failed: #{output}",
                  stdout: output,
                  stderr: '',
                  exit_status: status.exitstatus,
                )
        end

        CommandResult.new(output: output, exit_status: status.exitstatus)
      end

      def validate_stack_path!
        path = stack_path

        if path.blank?
          raise CommandError,
                'Stack path not configured. Set HELIOS_STACK_PATH environment variable.'
        end

        return if Dir.exist?(path)

        raise CommandError, "Stack path does not exist: #{path}"
      end

      def services_except_self
        compose_file = Compose.load
        compose_file.services.map(&:name) - [SELF_SERVICE]
      end
    end
  end
end
