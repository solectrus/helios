module Export
  class Env
    class SenecCharger < Section
      # CHARGER_* env var => [config field, default, comment]
      ENTRIES = {
        'CHARGER_INTERVAL' => ['interval', '3600', 'Seconds between charging checks'],
        'CHARGER_PRICE_MAX' => ['price_max', '70', 'Max acceptable average price vs. future rate (percent)'],
        'CHARGER_PRICE_TIME_RANGE' => ['price_time_range', '4', 'Hours required for a complete battery charge'],
        'CHARGER_FORECAST_THRESHOLD' => ['forecast_threshold', '20',
                                         'Min expected PV yield (kWh/24h) to skip grid charging'],
        'CHARGER_DRY_RUN' => ['dry_run', 'false', 'Test mode — prevents actual charging when true'],
      }.freeze

      def call
        return unless Services::SenecCharger.enabled?(configuration)

        charger = configuration.senec_charger
        env.add_section('SENEC charger')
        device_entries
        ENTRIES.each do |key, (field, default, comment)|
          entry(key, charger[field].presence || default, comment)
        end
      end

      private

      # The charger reaches the battery over its local API and has no adapter of
      # its own, so it needs SENEC_HOST/SENEC_SCHEMA whatever the collector
      # does. `Export::Env::Senec` already writes them when the collector polls
      # locally (it renders earlier, see Env::SECTIONS) — the two cases left are
      # a collector on the cloud adapter, which emits its credentials instead,
      # and no collector at all. Fill those in rather than let the container
      # start with an unresolved reference.
      def device_entries
        return if env.key?('SENEC_HOST')

        senec = configuration.senec
        entry('SENEC_HOST', senec.host, 'SENEC device IP or hostname — steered by the charger')
        entry('SENEC_SCHEMA', senec.schema || 'https', 'Connection protocol')
      end
    end
  end
end
