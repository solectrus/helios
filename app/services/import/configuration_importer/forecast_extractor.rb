module Import
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
        # Read the forecast measurement from the resolved service env so
        # indirections like INFLUX_MEASUREMENT=${FORECAST_INFLUX_MEASUREMENT}
        # (non-canonical variable name spotted in real-world stacks) round-trip
        # to the canonical INFLUX_MEASUREMENT_FORECAST on re-export.
        data['measurement'] = fc_env['INFLUX_MEASUREMENT'].presence
        data.compact.presence
      end

      private

      def base_data(fc_env)
        {
          'forecast' => fc_env['FORECAST_PROVIDER'],
          'forecast_latitude' => fc_env['FORECAST_LATITUDE'],
          'forecast_longitude' => fc_env['FORECAST_LONGITUDE'],
          'forecast_interval' => ::Forecast::IntervalRules.normalize(
            provider: fc_env['FORECAST_PROVIDER'],
            interval: fc_env['FORECAST_INTERVAL'],
          ),
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
        # Some installations declare a single roof with prefixed
        # FORECAST_0_DECLINATION/_AZIMUTH/_KWP instead of the unprefixed
        # slots — fall back to the prefixed values so the configuration
        # survives the round-trip.
        {
          'forecast_roofs' => '1',
          'forecast_declination1' => fc_env['FORECAST_DECLINATION'].presence || fc_env['FORECAST_0_DECLINATION'],
          azimuth_field(fc_env, 1) => fc_env['FORECAST_AZIMUTH'].presence || fc_env['FORECAST_0_AZIMUTH'],
          'forecast_kwp1' => fc_env['FORECAST_KWP'].presence || fc_env['FORECAST_0_KWP'],
        }
      end

      def multi_roof_data(fc_env, configs)
        # In the wild, some installations set a single unprefixed
        # FORECAST_DECLINATION shared by every roof while keeping AZIMUTH/KWP
        # per-roof — fan it out so the value survives the round-trip instead
        # of producing empty per-roof slots.
        global_declination = fc_env['FORECAST_DECLINATION']
        data = { 'forecast_roofs' => configs.to_s }
        configs.times do |i|
          data["forecast_declination#{i + 1}"] =
            fc_env["FORECAST_#{i}_DECLINATION"].presence || global_declination
          data[azimuth_field(fc_env, i + 1)] = fc_env["FORECAST_#{i}_AZIMUTH"]
          data["forecast_kwp#{i + 1}"] = fc_env["FORECAST_#{i}_KWP"]
        end
        data
      end

      def azimuth_field(fc_env, index)
        if fc_env['FORECAST_PROVIDER'] == 'pvnode'
          "forecast_pvnode_azimuth#{index}"
        else
          "forecast_azimuth#{index}"
        end
      end

      def provider_data(fc_env)
        case fc_env['FORECAST_PROVIDER']
        when 'forecast.solar'
          { 'forecast_solar_apikey' => fc_env['FORECAST_SOLAR_APIKEY'] }
        when 'solcast'
          {
            'forecast_solcast_api_key' => fc_env['SOLCAST_APIKEY'],
            'forecast_solcast_id1' => solcast_id1(fc_env),
            'forecast_solcast_id2' => fc_env['SOLCAST_1_SITE'],
          }
        when 'pvnode'
          pvnode_data(fc_env)
        else
          {}
        end
      end

      # Per upstream docs, multi-roof setups (FORECAST_CONFIGURATIONS >= 2) read
      # SOLCAST_0_SITE for roof 1; SOLCAST_SITE is the single-roof legacy alias
      # and ignored by the forecast-collector in multi-roof mode. Flip the
      # precedence so the importer matches the runtime value.
      def solcast_id1(fc_env)
        if fc_env['FORECAST_CONFIGURATIONS'].to_i > 1
          fc_env['SOLCAST_0_SITE'].presence || fc_env['SOLCAST_SITE']
        else
          fc_env['SOLCAST_SITE'].presence || fc_env['SOLCAST_0_SITE']
        end
      end

      def pvnode_data(fc_env)
        data = {
          'forecast_pvnode_apikey' => fc_env['PVNODE_APIKEY'],
          'forecast_pvnode_paid' => fc_env['PVNODE_PAID'],
          'forecast_pvnode_extra_params' => fc_env['PVNODE_EXTRA_PARAMS'],
        }
        configs = fc_env['FORECAST_CONFIGURATIONS']&.to_i || 1
        configs.times do |i|
          data["forecast_pvnode_extra_params#{i + 1}"] = fc_env["PVNODE_#{i}_EXTRA_PARAMS"]
        end
        data
      end
    end
  end
end
