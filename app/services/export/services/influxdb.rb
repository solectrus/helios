module Export
  module Services
    class Influxdb < Base
      def self.service_name
        'influxdb'
      end

      def self.config_keys
        ['influxdb']
      end

      def self.volume_env_key
        'INFLUX_VOLUME_PATH'
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
        config = {
          image: configuration.influxdb.image,
          environment: influxdb_environment,
          volumes: [bind_mount('/var/lib/influxdb2')],
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD', 'influx', 'ping'),
        }
        config[:ports] = ["#{host_port}:8086"] if publish_port?
        config
      end

      private

      # In dashboard_only mode the collectors run on a remote host and write
      # into this stack's InfluxDB across the LAN — so port 8086 has to be
      # reachable on the host regardless of the user's preference.
      def publish_port?
        configuration.dashboard_only? || configuration.influxdb.publish_port.present?
      end

      def host_port
        configuration.influxdb.host_port.presence || 8086
      end

      def influxdb_environment
        env = [
          'TZ',
          'DOCKER_INFLUXDB_INIT_MODE=setup',
          'DOCKER_INFLUXDB_INIT_USERNAME=admin',
          'DOCKER_INFLUXDB_INIT_PASSWORD=${INFLUX_PASSWORD}',
          'DOCKER_INFLUXDB_INIT_ORG=${INFLUX_ORG}',
          'DOCKER_INFLUXDB_INIT_BUCKET=${INFLUX_BUCKET}',
          'DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=${INFLUX_ADMIN_TOKEN}',
        ]
        env << 'INFLUXD_USE_HASHED_TOKENS' if configuration.influxdb.use_hashed_tokens.present?
        env
      end
    end
  end
end
