module Services
  class LogsController < BaseController
    TAIL_LINES = 200

    def show
      result = Orchestration::Runner.logs(service: service_name, tail: TAIL_LINES, timestamps: true)
      @log_html = format_log_output(result.output)
      @service_display_name = compose_service.display_name
    rescue Orchestration::Runner::CommandError => e
      @log_html = ERB::Util.html_escape(e.stdout.presence || e.message)
      @service_display_name = service_name
    end

    private

    def format_log_output(output)
      lines = output.lines.map(&:chomp)

      # Docker Compose interleaves output from replicas.
      # Only sort lines that have a timestamp prefix to preserve
      # multi-line context (stacktraces, continuation lines).
      timestamped, plain = lines.partition { |l| l.match?(LogLineFormatter::LINE_RE) }
      sorted = timestamped.sort + plain

      helpers.safe_join(sorted.map { |line| LogLineFormatter.call(line) })
    end
  end
end
