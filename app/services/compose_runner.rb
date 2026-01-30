require 'open3'

class ComposeRunner
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
    def up(detach: true)
      args = %w[up --no-build]
      args << '-d' if detach
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

    def start(service = nil)
      args = ['start']
      args << service if service
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

    private

    def run_compose(*args)
      validate_stack_path!

      cmd = ['docker', 'compose', '--progress', 'plain', *args.map(&:to_s)]

      output, status = Open3.capture2e(*cmd, chdir: stack_path)

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
  end

  class CommandResult
    attr_reader :output, :exit_status

    def initialize(output:, exit_status:)
      @output = output
      @exit_status = exit_status
    end

    def success?
      exit_status.zero?
    end

    def to_s
      output
    end

    def inspect
      status = success? ? 'success' : "failed(#{exit_status})"
      "#<CommandResult #{status}>\n#{output}"
    end
  end
end
