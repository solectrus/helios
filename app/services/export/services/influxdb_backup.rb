module Export
  module Services
    class InfluxdbBackup < Base
      def self.service_name
        'influxdb-backup'
      end

      def self.config_keys
        %w[backup influxdb]
      end

      def self.comment
        'InfluxDB Backup — Automated backup to S3'
      end

      def self.enabled?(configuration)
        !configuration.collectors_only? && configuration.configured?(:backup)
      end

      def to_h
        {
          image: configuration.backup.influxdb.image,
          environment: [
            'INFLUXDB_HOST=influxdb',
            'INFLUXDB_ORG=${INFLUX_ORG}',
            'INFLUXDB_TOKEN=${INFLUX_ADMIN_TOKEN}',
            'AWS_ACCESS_KEY_ID',
            'AWS_SECRET_ACCESS_KEY',
            'S3_BUCKET=${AWS_BUCKET}',
            'S3_PREFIX=influxdb_backup',
            'CRON=0 0 * * 0',
          ],
          depends_on: healthy_depends_on(%i[influxdb]),
          restart: 'unless-stopped',
        }
      end
    end
  end
end
