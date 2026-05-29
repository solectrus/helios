require 'open3'

module Orchestration
  # Thin wrappers around `docker` invocations shared by the detached
  # backup/restore runners. Each helper returns plain values so callers
  # can raise their own domain-specific errors with their own i18n keys.
  module DockerCli
    extend Loggable

    RunningContainer = Data.define(:started_at, :args)

    module_function

    def inspect_container(name)
      output, status = Open3.capture2e('docker', 'inspect', name)
      return nil unless status.success?

      JSON.parse(output).first
    rescue JSON::ParserError
      nil
    end

    def running_container(name)
      info = inspect_container(name)
      state = info&.dig('State')
      return nil unless state

      if state['Running']
        RunningContainer.new(
          started_at: Time.zone.parse(state['StartedAt']),
          args: Array(info['Args']),
        )
      else
        # Container exists but isn't running — the exited/removing window
        # that masks crashes from the UI (the SIGPIPE-141 restore.sh bug
        # surfaced exactly here). Logging fires once per such transition,
        # never during the steady "container absent" state.
        logger.info(
          "#{name} not running: status=#{state['Status'].inspect} " \
          "exit_code=#{state['ExitCode'].inspect} error=#{state['Error'].inspect}",
        )
        nil
      end
    end

    def pull_image(image)
      output, status = Open3.capture2e('docker', 'pull', image)
      [status.success?, output]
    end
  end
end
