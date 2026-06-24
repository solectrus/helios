module Export
  module Services
    class ForecastCollector < Base
      def self.service_name
        'forecast-collector'
      end

      def self.config_keys
        ['forecast']
      end

      def self.comment
        'Forecast Collector — Fetches solar production forecasts'
      end

      def self.enabled?(configuration)
        configuration.forecast_required? && configuration.forecast.forecast.present?
      end

      def to_h
        {
          image: configuration.forecast.image.presence || DockerImages.current(:FORECAST_COLLECTOR),
          environment: forecast_environment,
          depends_on: forecast_depends_on,
          restart: 'unless-stopped',
        }
      end

      # Targets InfluxDB directly, bypassing Ingest — forecast data must not be
      # rewritten by the house_power recalculation.
      def forecast_depends_on
        configuration.collectors_only? ? nil : healthy_depends_on(%i[influxdb])
      end

      private

      def forecast_environment
        return passthrough_vars + explicit_vars + pvnode_v2_vars if configuration.forecast_pvnode_v2?

        passthrough_vars + explicit_vars + forecast_vars + roof_vars + optional_vars + provider_vars
      end

      def pvnode_v2_vars
        ::Forecast::PvnodeRules.v2_env_keys(configuration.forecast.forecast_pvnode_paid)
      end

      def passthrough_vars
        vars = %w[TZ INFLUX_ORG INFLUX_BUCKET]
        vars += ConfigSchema::INFLUXDB_EXTERNAL_ENV_KEYS if configuration.collectors_only?
        vars
      end

      def explicit_vars
        measurement = 'INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_FORECAST}'
        return [influx_token_write_var, measurement] if configuration.collectors_only?

        ['INFLUX_HOST=influxdb', influx_token_write_var, measurement]
      end

      def forecast_vars
        vars = %w[FORECAST_PROVIDER FORECAST_LATITUDE FORECAST_LONGITUDE]
        vars << 'FORECAST_INTERVAL' if forecast_interval_emitted?
        vars
      end

      def forecast_interval_emitted?
        fcast = configuration.forecast
        ::Forecast::IntervalRules.emit_value(provider: fcast.forecast,
                                             interval: fcast.forecast_interval).present?
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
        fcast = configuration.forecast
        vars = %w[PVNODE_APIKEY]
        vars << 'PVNODE_PAID' if pvnode_paid_plan?(fcast.forecast_pvnode_paid)
        vars << 'PVNODE_EXTRA_PARAMS' if fcast.forecast_pvnode_extra_params.present?
        roofs = (fcast.forecast_roofs || 1).to_i
        roofs.times do |i|
          vars << "PVNODE_#{i}_EXTRA_PARAMS" if fcast.send("forecast_pvnode_extra_params#{i + 1}").present?
        end
        vars
      end

      def pvnode_paid_plan?(value)
        ::Forecast::PvnodeRules.paid_plan?(value)
      end
    end
  end
end
