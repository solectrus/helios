module Services
  class LogsController < BaseController
    TAIL_LINES = 200

    def show
      if params[:until].present?
        show_older_logs
      else
        show_initial_logs
      end
    end

    private

    def show_initial_logs
      result = Orchestration::Runner.logs(service: service_name, tail: TAIL_LINES, timestamps: true)
      @log_html = format_log_html(result.output.lines.map(&:chomp))
      @service_display_name = compose_service.display_name
    rescue Orchestration::Runner::CommandError => e
      @log_html = ERB::Util.html_escape(e.stdout.presence || e.message)
      @service_display_name = service_name
    end

    def show_older_logs
      result = Orchestration::Runner.logs(
        service: service_name,
        timestamps: true,
        until_timestamp: params[:until],
      )

      lines = result.output.lines.map(&:chomp).compact_blank
      html = format_log_html(lines.last(TAIL_LINES))
      render html: html, layout: false
    rescue Orchestration::Runner::CommandError
      render html: '', layout: false
    end

    def format_log_html(lines)
      # Docker Compose interleaves output from replicas.
      # Only sort lines that have a timestamp prefix to preserve
      # multi-line context (stacktraces, continuation lines).
      timestamped, plain = lines.partition { |l| l.match?(LogLineFormatter::LINE_RE) }
      sorted = timestamped.sort + plain

      helpers.safe_join(sorted.map { |line| LogLineFormatter.call(line) })
    end
  end
end
