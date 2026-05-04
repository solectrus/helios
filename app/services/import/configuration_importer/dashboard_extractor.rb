module Import
  class ConfigurationImporter
    class DashboardExtractor
      include Helpers

      def initialize(reader)
        @reader = reader
      end

      def section_data
        dashboard_env = service_env('dashboard')

        image_data_for('dashboard').merge(
          'co2_emission_factor' => dashboard_env['CO2_EMISSION_FACTOR'],
          'frame_ancestors' => dashboard_env['FRAME_ANCESTORS'],
          'ui_theme' => dashboard_env['UI_THEME'],
          'lockup_codeword' => dashboard_env['LOCKUP_CODEWORD'],
          'trusted_proxy_ranges' => dashboard_env['TRUSTED_PROXY_RANGES'],
        ).compact
      end
    end
  end
end
