require 'open3'
require 'timeout'

module Orchestration
  # Thin wrappers around `docker` invocations, shared by the detached
  # backup/restore runners and by request threads reading a container log.
  # Each helper returns plain values so callers can raise their own
  # domain-specific errors with their own i18n keys.
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

    # Last `lines` lines of a container's log. Deliberately the CLI and not
    # docker-api, whose non-TTY log stream is multiplexed and would have to be
    # de-framed. Read from request threads on every poll, so a hung Docker
    # daemon must not pile up Puma workers — the timeout is generous because a
    # tail read is normally sub-second. Returns '' when the log is unreadable.
    LOG_TAIL_TIMEOUT = 5

    def log_tail(name, lines:, timestamps: false)
      command = ['docker', 'logs', '--tail', lines.to_s]
      command << '--timestamps' if timestamps

      Timeout.timeout(LOG_TAIL_TIMEOUT) do
        output, = Open3.capture2e(*command, name)
        output
      end
    rescue StandardError
      ''
    end

    def pull_image(image)
      output, status = Open3.capture2e('docker', 'pull', image)
      [status.success?, output]
    end

    # Force-removes a single container by name or id (`docker rm -f`). Used to
    # clear a stale container that blocks `compose up` with a name conflict.
    # Data is unaffected: SOLECTRUS stores it in bind mounts, not the container.
    # Returns [success, output].
    def force_remove_container(name)
      output, status = Open3.capture2e('docker', 'rm', '--force', name)
      [status.success?, output]
    end
  end
end
