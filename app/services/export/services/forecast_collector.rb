module Export
  module Services
    class ForecastCollector < Base
      def self.service_name
        'forecast-collector'
      end

      def self.comment
        'Forecast Collector — Fetches solar production forecasts'
      end

      def self.enabled?(configuration)
        configuration.forecast_required? &&
          configuration.forecast.forecast.present? &&
          configuration.forecast.forecast != 'none'
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
        passthrough_vars + explicit_vars + optional_vars + roof_vars + provider_vars
      end

      def passthrough_vars
        %w[TZ INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET
           FORECAST_PROVIDER FORECAST_LATITUDE FORECAST_LONGITUDE FORECAST_INTERVAL]
      end

      def explicit_vars
        ['INFLUX_HOST=influxdb', 'INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_FORECAST}']
      end

      def optional_vars
        fcast = configuration.forecast
        vars = []
        vars << 'FORECAST_DAMPING_MORNING' if fcast.forecast_damping_morning.present?
        vars << 'FORECAST_DAMPING_EVENING' if fcast.forecast_damping_evening.present?
        vars << 'FORECAST_HORIZON' if fcast.forecast_horizon.present?
        vars << 'FORECAST_INVERTER' if fcast.forecast_inverter.present?
        vars
      end

      def roof_vars
        roofs = (configuration.forecast.forecast_roofs || 1).to_i
        return %w[FORECAST_DECLINATION FORECAST_AZIMUTH FORECAST_KWP] unless roofs > 1

        multi_roof_vars(roofs)
      end

      def multi_roof_vars(roofs)
        vars = %w[FORECAST_CONFIGURATIONS]
        roofs.times do |i|
          vars << "FORECAST_#{i}_DECLINATION"
          vars << "FORECAST_#{i}_AZIMUTH"
          vars << "FORECAST_#{i}_KWP"
        end
        vars
      end

      def provider_vars
        case configuration.forecast.forecast
        when 'forecast.solar' then forecast_solar_vars
        when 'solcast' then %w[SOLCAST_APIKEY SOLCAST_SITE]
        when 'pvnode' then pvnode_vars
        else []
        end
      end

      def forecast_solar_vars
        configuration.forecast.forecast_solar_apikey.present? ? %w[FORECAST_SOLAR_APIKEY] : []
      end

      def pvnode_vars
        vars = %w[PVNODE_APIKEY]
        vars << 'PVNODE_PAID' if configuration.forecast.forecast_pvnode_paid.present?
        vars << 'PVNODE_EXTRA_PARAMS' if configuration.forecast.forecast_pvnode_extra_params.present?
        vars
      end
    end
  end
end
