module Import
  class ConfigurationImporter
    class WatchtowerExtractor
      include Helpers

      def initialize(reader)
        @reader = reader
      end

      def section_data
        image_data_for('watchtower')
      end

      # WATCHTOWER_POLL_INTERVAL takes precedence; some installations configure
      # the interval inline on the watchtower service (`environment:` block) or
      # as a `--interval N` argument on its command, which are equally valid for
      # Watchtower itself.
      def interval
        env_value = @reader.raw_env['WATCHTOWER_POLL_INTERVAL'].presence ||
                    service_env('watchtower')['WATCHTOWER_POLL_INTERVAL'].presence
        return env_value if env_value

        command = @reader.service('watchtower')&.dig('command')
        tokens = Array(command).flat_map { |part| part.to_s.split }
        index = tokens.index('--interval')
        tokens[index + 1] if index && tokens[index + 1]
      end

      # The cron expression of an installation that checks at a fixed time
      # instead of polling. Same precedence as #interval. Whether HELIOS can
      # represent the expression at all is decided by the caller (see
      # WatchtowerSchedule.time_of_day).
      def schedule
        @reader.raw_env['WATCHTOWER_SCHEDULE'].presence ||
          service_env('watchtower')['WATCHTOWER_SCHEDULE'].presence ||
          command_schedule
      end

      private

      def command_schedule
        parts = Array(@reader.service('watchtower')&.dig('command'))

        # List form keeps the cron in one element: ["--schedule", "0 0 4 * * *"]
        index = parts.index('--schedule')
        return parts[index + 1] if index && parts[index + 1]

        # String form arrives shell-style, where a cron has to be quoted to
        # survive as a single argument.
        parts.join(' ')[/--schedule[=\s]+["']([^"']+)["']/, 1]
      end
    end
  end
end
