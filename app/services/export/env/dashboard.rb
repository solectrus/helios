module Export
  class Env
    class Dashboard < Section
      def call
        env.add_section('Dashboard')
        entry('APP_HOST', configuration.system.app_host.presence || 'localhost',
              'Hostname for the SOLECTRUS web interface')
        optional_entries(configuration.dashboard)
      end

      private

      def optional_entries(dashboard)
        optional_entry('CO2_EMISSION_FACTOR', dashboard.co2_emission_factor, 'CO2 emission factor (g/kWh)')
        optional_entry('FRAME_ANCESTORS', dashboard.frame_ancestors, 'Allowed frame ancestors for embedding')
        optional_entry('UI_THEME', dashboard.ui_theme, 'UI theme (light or dark)')
        optional_entry('LOCKUP_CODEWORD', dashboard.lockup_codeword, 'Codeword for lockup page protection')
        optional_entry('TRUSTED_PROXY_RANGES', dashboard.trusted_proxy_ranges, 'Trusted proxy IP ranges')
        excluded = configuration.excluded_from_house_power.join(',').presence
        optional_entry('INFLUX_EXCLUDE_FROM_HOUSE_POWER', excluded,
                       'Sensors excluded from house power calculation')
      end
    end
  end
end
