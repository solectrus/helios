class StackBuilder
  module Services
    class Influxdb < Base
      def self.service_name
        'influxdb'
      end

      def self.comment
        'Time-series database for sensor measurements'
      end

      def self.data_directories
        ['influxdb']
      end

      def to_h
        {
          image: configuration.system.influxdb_image || 'influxdb:2-alpine',
          ports: ['8086:8086'],
          environment: influxdb_environment,
          volumes: ['./influxdb:/var/lib/influxdb2'],
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD', 'influx', 'ping'),
        }
      end

      private

      def influxdb_environment
        {
          'DOCKER_INFLUXDB_INIT_MODE' => 'setup',
          'DOCKER_INFLUXDB_INIT_USERNAME' => 'admin',
          'DOCKER_INFLUXDB_INIT_PASSWORD' => '${INFLUX_PASSWORD}',
          'DOCKER_INFLUXDB_INIT_ORG' => '${INFLUX_ORG}',
          'DOCKER_INFLUXDB_INIT_BUCKET' => '${INFLUX_BUCKET}',
          'DOCKER_INFLUXDB_INIT_ADMIN_TOKEN' => '${INFLUX_TOKEN}',
        }
      end
    end
  end
end
