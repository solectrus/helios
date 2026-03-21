class ConfigurationImporter
  class ForecastExtractor
    include Helpers

    def initialize(reader)
      @reader = reader
    end

    def enabled?
      @reader.services.key?('forecast-collector')
    end

    def section_data
      return unless enabled?

      fc_env = service_env('forecast-collector')
      data = base_data(fc_env)
      data.merge!(roof_data(fc_env))
      data.merge!(provider_data(fc_env))
      data.compact.presence
    end

    private

    def base_data(fc_env)
      {
        'forecast' => fc_env['FORECAST_PROVIDER'],
        'forecast_latitude' => fc_env['FORECAST_LATITUDE'],
        'forecast_longitude' => fc_env['FORECAST_LONGITUDE'],
        'forecast_interval' => fc_env['FORECAST_INTERVAL'],
        'forecast_damping_morning' => fc_env['FORECAST_DAMPING_MORNING'],
        'forecast_damping_evening' => fc_env['FORECAST_DAMPING_EVENING'],
        'forecast_horizon' => fc_env['FORECAST_HORIZON'],
        'forecast_inverter' => fc_env['FORECAST_INVERTER'],
      }
    end

    def roof_data(fc_env)
      configs = fc_env['FORECAST_CONFIGURATIONS']&.to_i
      return single_roof_data(fc_env) unless configs && configs > 1

      multi_roof_data(fc_env, configs)
    end

    def single_roof_data(fc_env)
      {
        'forecast_roofs' => '1',
        'forecast_declination1' => fc_env['FORECAST_DECLINATION'],
        'forecast_azimuth1' => fc_env['FORECAST_AZIMUTH'],
        'forecast_kwp1' => fc_env['FORECAST_KWP'],
      }
    end

    def multi_roof_data(fc_env, configs)
      data = { 'forecast_roofs' => configs.to_s }
      configs.times do |i|
        data["forecast_declination#{i + 1}"] = fc_env["FORECAST_#{i}_DECLINATION"]
        data["forecast_azimuth#{i + 1}"] = fc_env["FORECAST_#{i}_AZIMUTH"]
        data["forecast_kwp#{i + 1}"] = fc_env["FORECAST_#{i}_KWP"]
      end
      data
    end

    def provider_data(fc_env) # rubocop:disable Metrics/MethodLength
      case fc_env['FORECAST_PROVIDER']
      when 'forecast.solar'
        { 'forecast_solar_apikey' => fc_env['FORECAST_SOLAR_APIKEY'] }
      when 'solcast'
        {
          'forecast_solcast_api_key' => fc_env['SOLCAST_APIKEY'],
          'forecast_solcast_id1' => fc_env['SOLCAST_SITE'] || fc_env['SOLCAST_0_SITE'],
          'forecast_solcast_id2' => fc_env['SOLCAST_1_SITE'],
        }
      when 'pvnode'
        {
          'forecast_pvnode_apikey' => fc_env['PVNODE_APIKEY'],
          'forecast_pvnode_paid' => fc_env['PVNODE_PAID'],
          'forecast_pvnode_extra_params' => fc_env['PVNODE_EXTRA_PARAMS'],
        }
      else
        {}
      end
    end
  end
end
