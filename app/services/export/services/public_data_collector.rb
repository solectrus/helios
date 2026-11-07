module Export
  module Services
    class PublicDataCollector < Base
      def self.service_name
        'public-data-collector'
      end

      def self.config_keys
        ['public_data_collector']
      end

      def self.comment
        'Public Data Collector — Fetches public fuel prices'
      end

      # The dashboard compares a car with a combustion car of the same
      # mileage, which only an odometer gives, and the heat pump with an oil
      # or a gas heating that makes the same heat, which only the sensor of
      # the generated heat gives. The sources of the prices cover the European
      # Union. The prices are in euros, and the dashboard shows them for that
      # currency alone.
      def self.enabled?(configuration)
        return false if configuration.collectors_only?

        configuration.develop_dashboard? &&
          (configuration.mapped_car_roles.include?('car_odometer') || heating_comparison?(configuration)) &&
          configuration.country.present? &&
          configuration.currency == 'EUR'
      end

      # { switch => measurement } of each source that the collector reads.
      # The fuel prices hold heating oil too.
      SOURCES = { 'ENABLE_FUEL' => 'Fuel', 'ENABLE_GAS' => 'Gas' }.freeze
      private_constant :SOURCES

      # The measurements the collector writes into, none while it does not
      # run. Their names are fixed.
      def self.measurements(configuration) = sources(configuration).values

      def self.sources(configuration)
        return {} unless enabled?(configuration)

        heating_comparison?(configuration) ? SOURCES : SOURCES.slice('ENABLE_FUEL')
      end

      # The dashboard reads the fuel of the heating from its own settings, so
      # the collector fetches heating oil and natural gas both.
      def self.heating_comparison?(configuration)
        configuration.effective_sensor_mappings.key?('heatpump_heating_power')
      end
      private_class_method :heating_comparison?

      def to_h
        {
          image: configuration.public_data_collector.image.presence ||
            DockerImages.current(:PUBLIC_DATA_COLLECTOR),
          environment: passthrough_vars + explicit_vars,
          depends_on: influxdb_depends_on,
          restart: 'unless-stopped',
        }
      end

      private

      def passthrough_vars
        super + ['COUNTRY']
      end

      # Reads the bucket once at start, to write the price history only from
      # where the other data begins.
      def explicit_vars
        influx_endpoint_vars + [influx_token_readwrite_var] +
          self.class.sources(configuration).keys.map { "#{it}=true" }
      end
    end
  end
end
