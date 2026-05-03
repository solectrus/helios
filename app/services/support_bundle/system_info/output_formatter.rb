module SupportBundle
  module SystemInfo
    # Pure presentation helpers: section/table rendering, shell capture, byte
    # formatting. Knows nothing about the host or Docker — the metric and
    # report modules call into it for output and small primitive conversions.
    module OutputFormatter
      module_function

      def format_section(title, body)
        ["=== #{title} ===", *format_body(body), ''].join("\n")
      end

      def format_body(body)
        return body.to_s.lines.map(&:chomp) if body.is_a?(String)

        width = body.keys.map(&:length).max || 0
        body.map { |key, value| "#{key.to_s.ljust(width)}  #{format_value(value)}" }
      end

      def format_value(value)
        return value.to_s unless value.is_a?(String) && value.include?("\n")

        "\n#{value.chomp.lines.map { |l| "  #{l}" }.join}"
      end

      def render_table(headers, rows)
        widths = column_widths(headers, rows)
        [headers, *rows].map { |row| render_row(row, widths) }.join("\n")
      end

      def column_widths(headers, rows)
        headers.each_with_index.map do |header, i|
          ([header.length] + rows.map { |row| row[i].to_s.length }).max
        end
      end

      def render_row(row, widths)
        row.each_with_index.map { |cell, i| cell.to_s.ljust(widths[i]) }.join('  ').rstrip
      end

      def capture(*)
        output, status = Open3.capture2e(*)
        return "failed (exit #{status.exitstatus}): #{output.strip}" unless status.success?

        output.strip
      rescue StandardError => e
        "unavailable: #{e.class}: #{e.message}"
      end

      def human_bytes(bytes)
        return 'unknown' unless bytes.is_a?(Numeric)

        ActiveSupport::NumberHelper.number_to_human_size(bytes)
      end

      def kb_to_human(kibibytes)
        human_bytes(kibibytes.to_i * 1024)
      end

      def value_after(line, separator)
        return nil unless line

        parts = line.split(separator, 2)
        return nil if parts.length < 2

        parts.last.strip
      end

      def int_or_nil(raw)
        raw.to_s.match?(/\A-?\d+\z/) ? raw.to_i : nil
      end
    end
  end
end
