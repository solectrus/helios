module Import
  class ConfigurationImporter
    # Extracts the senec-charger tuning parameters into the managed
    # `senec_charger` config section.
    #
    # The charger is always a managed HELIOS service, never `_unmanaged`. HELIOS
    # only reproduces it where all three of its dependencies hold: the
    # tibber-collector (writes the prices it reads), the forecast-collector
    # (writes the yield it reads) and a locally polled SENEC battery (the device
    # it steers — it talks to the local API and knows no adapter of its own, so
    # a cloud-polled battery leaves no address to configure it with).
    #
    # A charger missing any of them cannot work as configured and is dropped
    # rather than imported. The drop is logged: the container is running right
    # now and will be gone after the import.
    class SenecChargerExtractor
      include Helpers
      include Loggable

      def initialize(reader)
        @reader = reader
      end

      def enabled?
        @reader.services.key?('senec-charger') && drop_reasons.empty?
      end

      def section_data
        unless enabled?
          log_drop
          return
        end

        charger_env = service_env('senec-charger')
        data = {
          'interval' => charger_env['CHARGER_INTERVAL'],
          'price_max' => charger_env['CHARGER_PRICE_MAX'],
          'price_time_range' => charger_env['CHARGER_PRICE_TIME_RANGE'],
          'forecast_threshold' => charger_env['CHARGER_FORECAST_THRESHOLD'],
          'dry_run' => boolean_or_nil(charger_env['CHARGER_DRY_RUN']),
        }.compact.presence
        # The image carries the pinned release channel, so it is captured to
        # round-trip on re-export. Only added to a section that exists: an image
        # alone leaves the charger unconfigured (Configuration#senec_charger_enabled?).
        data&.merge(image_data_for('senec-charger'))
      end

      private

      # The survey persists dry_run as a boolean, so the import has to as well:
      # the raw 'true' string matches neither of a SurveyJS boolean question's
      # valueTrue/valueFalse, which would render an imported test mode as off
      # and turn real charging on at the next save.
      def boolean_or_nil(value)
        return nil if value.blank?

        value.to_s == 'true'
      end

      # The senec-collector defaults to local access; only an explicit `cloud`
      # adapter rules out the charger.
      def senec_local?
        service_env('senec-collector')['SENEC_ADAPTER'].to_s != 'cloud'
      end

      # Why this charger can't be reproduced — empty means it can. Doubles as
      # the gate (#enabled?) and as the log message, so the two can't drift.
      def drop_reasons
        reasons = []
        reasons << 'no tibber-collector to read prices from' unless @reader.services.key?('tibber-collector')
        reasons << 'no forecast-collector to read the yield from' unless @reader.services.key?('forecast-collector')
        reasons << 'the battery is polled through the cloud, leaving no local API to steer' unless senec_local?
        reasons
      end

      # Name the drop rather than let the user discover it by absence: the
      # container is running right now and will be gone after the import.
      def log_drop
        return unless @reader.services.key?('senec-charger')

        logger.info("dropping senec-charger, cannot reproduce it: #{drop_reasons.join('; ')}")
      end
    end
  end
end
