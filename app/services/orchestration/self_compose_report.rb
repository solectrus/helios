module Orchestration
  # What the helper container of the last self-update or converge left behind.
  #
  # That run ends the process that starts it, so nothing in HELIOS sees how it
  # went (see DetachedCompose). The helper therefore keeps its name and its
  # exit code until someone reads them, which is what this does: it reports a
  # run that failed, once, and clears the container either way.
  #
  # The reader is the services screen, the first screen HELIOS shows after it
  # comes back. A run that fails leaves a stack that is half recreated, and
  # that screen is where the user is looking for the reason.
  class SelfComposeReport
    CONTAINER_NAME = DetachedCompose::CONTAINER_NAME

    # Lines of the helper log to carry into the message. Compose prints one
    # line per container, so the reason stands at the end.
    LOG_LINES = 20

    class << self
      # The last line of the failed run, or nil where the last run succeeded,
      # is still going, or never happened. The container goes with the answer,
      # so the same failure is never reported twice.
      def collect!
        state = DockerCli.inspect_container(CONTAINER_NAME)&.dig('State')
        return if state.nil? || state['Running']

        reason = failure_reason(state)
        DockerCli.force_remove_container(CONTAINER_NAME)
        reason
      end

      private

      def failure_reason(state)
        return if state['ExitCode'].to_i.zero?

        log = DockerCli.log_tail(CONTAINER_NAME, lines: LOG_LINES)
        log.lines.map(&:strip).compact_blank.last.presence ||
          "exit code #{state['ExitCode']}"
      end
    end
  end
end
