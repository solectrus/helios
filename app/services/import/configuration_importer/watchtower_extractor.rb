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
    end
  end
end
