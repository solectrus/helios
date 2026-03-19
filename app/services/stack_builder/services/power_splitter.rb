class StackBuilder
  module Services
    class PowerSplitter < Base
      def self.service_name
        'power-splitter'
      end

      def self.comment
        'Calculates derived power values'
      end

      def self.enabled?(configuration)
        configuration.ingest_required?
      end

      def to_h
        {
          image: 'ghcr.io/solectrus/power-splitter:latest',
          environment: power_splitter_environment,
          depends_on: healthy_depends_on(%i[influxdb postgresql redis]),
          restart: 'unless-stopped',
        }
      end

      private

      def power_splitter_environment
        base_environment.merge(optional_environment).merge(sensor_environment)
      end

      def base_environment
        {
          'TZ' => '${TZ}',
          'INSTALLATION_DATE' => '${INSTALLATION_DATE}',
          'INFLUX_HOST' => 'influxdb',
          'INFLUX_TOKEN' => '${INFLUX_TOKEN}',
          'INFLUX_ORG' => '${INFLUX_ORG}',
          'INFLUX_BUCKET' => '${INFLUX_BUCKET}',
          'REDIS_URL' => 'redis://redis:6379/1',
          'DB_HOST' => 'postgresql',
          'DB_USER' => 'postgres',
          'DB_PASSWORD' => '${POSTGRES_PASSWORD}',
        }
      end

      def optional_environment
        env = {}
        interval = configuration.system.power_splitter_interval
        env['POWER_SPLITTER_INTERVAL'] = interval if interval.present?
        env
      end

      def sensor_environment
        configuration.effective_sensor_mappings.each_with_object({}) do |(sensor, mapping), env|
          next if mapping.blank?

          env["INFLUX_SENSOR_#{sensor.upcase}"] = "${INFLUX_SENSOR_#{sensor.upcase}}"
        end
      end
    end
  end
end
