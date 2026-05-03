module Export
  class Env
    class Influxdb < Section
      def call
        if configuration.collectors_only?
          external_section
        else
          local_section
        end
      end

      private

      def local_section
        env.add_section('InfluxDB time-series database')
        local_required_entries
        optional_entry('INFLUXD_USE_HASHED_TOKENS', configuration.influxdb.use_hashed_tokens,
                       'Store API tokens as bcrypt hashes (imported from existing installation)')
        volume_path_entry(Services::Influxdb, 'InfluxDB data')
      end

      def local_required_entries
        entry('INFLUX_PASSWORD', configuration.influxdb.password,
              'Admin password — auto-generated, do not change after first start')
        entry('INFLUX_ORG', configuration.influxdb.org, 'Organization name')
        entry('INFLUX_BUCKET', configuration.influxdb.bucket,
              'Bucket (database) name for time-series data')
        entry('INFLUX_TOKEN', configuration.influxdb.token,
              'API token with full access — auto-generated, do not change after first start')
      end

      def external_section
        influx = configuration.influxdb
        env.add_section('External InfluxDB target')
        entry('INFLUX_HOST', influx.host, 'Hostname of the external InfluxDB instance')
        entry('INFLUX_PORT', influx.port.presence || '8086', 'Port of the external InfluxDB instance')
        entry('INFLUX_SCHEMA', influx.schema.presence || 'https', 'Protocol (http or https)')
        entry('INFLUX_ORG', influx.org, 'Organization name')
        entry('INFLUX_BUCKET', influx.bucket, 'Bucket (database) name for time-series data')
        entry('INFLUX_TOKEN', influx.token, 'API token with write access')
      end
    end
  end
end
