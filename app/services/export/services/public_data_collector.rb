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
      # mileage, which only an odometer gives. The Weekly Oil Bulletin, which
      # the collector reads the fuel prices from, covers the European Union.
      # Its prices are in euros, and the dashboard shows them for that
      # currency alone.
      def self.enabled?(configuration)
        return false if configuration.collectors_only?

        configuration.develop_dashboard? &&
          configuration.mapped_car_roles.include?('car_odometer') &&
          configuration.country.present? &&
          configuration.currency == 'EUR'
      end

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
        influx_endpoint_vars + [influx_token_readwrite_var, 'ENABLE_FUEL=true']
      end
    end
  end
end
