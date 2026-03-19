class StackBuilder
  module Services
    class ForecastCollector < Base
      def self.service_name
        'forecast-collector'
      end

      def self.comment
        'Solar forecast data collector'
      end

      def self.enabled?(configuration)
        configuration.forecast.forecast.present?
      end

      def to_h
        {
          image: 'ghcr.io/solectrus/forecast-collector:latest',
          environment: forecast_environment,
          depends_on: healthy_depends_on(%i[influxdb]),
          restart: 'unless-stopped',
        }
      end

      private

      def forecast_environment
        base_environment
          .merge(optional_environment)
          .merge(roof_environment)
          .merge(provider_environment)
      end

      def base_environment
        {
          'TZ' => '${TZ}',
          'INFLUX_HOST' => 'influxdb',
          'INFLUX_TOKEN' => '${INFLUX_TOKEN}',
          'INFLUX_ORG' => '${INFLUX_ORG}',
          'INFLUX_BUCKET' => '${INFLUX_BUCKET}',
          'INFLUX_MEASUREMENT' => '${INFLUX_MEASUREMENT_FORECAST}',
          'FORECAST_PROVIDER' => '${FORECAST_PROVIDER}',
          'FORECAST_LATITUDE' => '${FORECAST_LATITUDE}',
          'FORECAST_LONGITUDE' => '${FORECAST_LONGITUDE}',
          'FORECAST_INTERVAL' => '${FORECAST_INTERVAL}',
        }
      end

      def roof_environment
        roofs = (configuration.forecast.forecast_roofs || 1).to_i
        return single_roof_environment unless roofs > 1

        multi_roof_environment(roofs)
      end

      def single_roof_environment
        {
          'FORECAST_DECLINATION' => '${FORECAST_DECLINATION}',
          'FORECAST_AZIMUTH' => '${FORECAST_AZIMUTH}',
          'FORECAST_KWP' => '${FORECAST_KWP}',
        }
      end

      def multi_roof_environment(roofs)
        env = { 'FORECAST_CONFIGURATIONS' => '${FORECAST_CONFIGURATIONS}' }
        roofs.times do |i|
          env["FORECAST_#{i}_DECLINATION"] = "${FORECAST_#{i}_DECLINATION}"
          env["FORECAST_#{i}_AZIMUTH"] = "${FORECAST_#{i}_AZIMUTH}"
          env["FORECAST_#{i}_KWP"] = "${FORECAST_#{i}_KWP}"
        end
        env
      end

      def optional_environment
        fcast = configuration.forecast
        env = {}
        env['FORECAST_DAMPING_MORNING'] = '${FORECAST_DAMPING_MORNING}' if fcast.forecast_damping_morning.present?
        env['FORECAST_DAMPING_EVENING'] = '${FORECAST_DAMPING_EVENING}' if fcast.forecast_damping_evening.present?
        env['FORECAST_HORIZON'] = '${FORECAST_HORIZON}' if fcast.forecast_horizon.present?
        env['FORECAST_INVERTER'] = '${FORECAST_INVERTER}' if fcast.forecast_inverter.present?
        env
      end

      def provider_environment
        case configuration.forecast.forecast
        when 'forecast.solar' then forecast_solar_environment
        when 'solcast' then solcast_environment
        when 'pvnode' then pvnode_environment
        else {}
        end
      end

      def forecast_solar_environment
        return {} if configuration.forecast.forecast_solar_apikey.blank?

        { 'FORECAST_SOLAR_APIKEY' => '${FORECAST_SOLAR_APIKEY}' }
      end

      def solcast_environment
        {
          'SOLCAST_APIKEY' => '${SOLCAST_APIKEY}',
          'SOLCAST_SITE' => '${SOLCAST_SITE}',
        }
      end

      def pvnode_environment
        env = { 'PVNODE_APIKEY' => '${PVNODE_APIKEY}' }
        env['PVNODE_PAID'] = '${PVNODE_PAID}' if configuration.forecast.forecast_pvnode_paid.present?
        if configuration.forecast.forecast_pvnode_extra_params.present?
          env['PVNODE_EXTRA_PARAMS'] =
            '${PVNODE_EXTRA_PARAMS}'
        end
        env
      end
    end
  end
end
