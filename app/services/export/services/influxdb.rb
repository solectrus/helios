module Export
  module Services
    class Influxdb < Base
      def self.service_name
        'influxdb'
      end

      def self.comment
        'InfluxDB — Time-series database for sensor measurements'
      end

      def self.enabled?(configuration)
        !configuration.collectors_only?
      end

      def data_directories
        managed_data_directory
      end

      def to_h
        {
          image: configuration.influxdb.image,
          ports: ['8086:8086'],
          environment: [
            'DOCKER_INFLUXDB_INIT_MODE=setup',
            'DOCKER_INFLUXDB_INIT_USERNAME=admin',
            'DOCKER_INFLUXDB_INIT_PASSWORD=${INFLUX_PASSWORD}',
            'DOCKER_INFLUXDB_INIT_ORG=${INFLUX_ORG}',
            'DOCKER_INFLUXDB_INIT_BUCKET=${INFLUX_BUCKET}',
            'DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=${INFLUX_TOKEN}',
          ],
          volumes: [bind_mount('/var/lib/influxdb2')],
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD', 'influx', 'ping'),
        }
      end
    end
  end
end
