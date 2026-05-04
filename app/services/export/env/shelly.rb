module Export
  class Env
    class Shelly < Section
      def call
        return collectors_only_section if configuration.collectors_only?

        sensors = configuration.sensors_with_source('shelly')
        return if sensors.blank?

        shelly = configuration.shelly
        env.add_section('Shelly collector')
        host_entry(sensors, shelly)
        entry('SHELLY_INTERVAL', shelly&.interval || '5',
              'Polling interval in seconds')
        entry('INFLUX_MEASUREMENT', csv(sensors) { |_, config| config['measurement'] },
              'InfluxDB measurement names (comma-separated)')
        optional_entries(sensors, shelly)
      end

      private

      def host_entry(sensors, shelly)
        return if shelly&.connection == 'cloud'

        entry('SHELLY_HOST', csv(sensors) { |_, config| config['shelly_host'] },
              'Shelly device hostnames (comma-separated)')
      end

      def collectors_only_section
        shelly = configuration.shelly
        devices = Array(shelly&.devices)
        return if devices.empty?

        env.add_section('Shelly collector')
        entry('SHELLY_INTERVAL', shelly.interval || '5', 'Polling interval in seconds')
        collectors_only_device_entries(devices, shelly)
        collectors_only_extra_entries(shelly)
        global_optional_entries(shelly)
      end

      def collectors_only_device_entries(devices, shelly)
        if shelly&.connection == 'cloud'
          ids = devices.filter_map { |d| d['device_id'].presence }.join(',')
          optional_entry('SHELLY_DEVICE_ID', ids, 'Shelly cloud device IDs (comma-separated)')
        else
          hosts = devices.filter_map { |d| d['host'].presence }.join(',')
          optional_entry('SHELLY_HOST', hosts, 'Shelly device hostnames (comma-separated)')
        end

        measurements = devices.filter_map { |d| d['measurement'].presence }.join(',')
        optional_entry('INFLUX_MEASUREMENT', measurements,
                       'InfluxDB measurement names (comma-separated)')
      end

      def collectors_only_extra_entries(shelly)
        optional_entry('INFLUX_MODE', shelly.mode, 'InfluxDB write mode (essential or full)')
        optional_entry('SHELLY_PASSWORD', shelly.password, 'Shelly device password')
      end

      def optional_entries(sensors, shelly)
        per_sensor_optional_entries(sensors)
        global_optional_entries(shelly)
      end

      def per_sensor_optional_entries(sensors)
        %w[shelly_password shelly_device_id shelly_invert_power].each do |field|
          values = sensors.map { |_, config| config[field].presence || '' }
          next unless values.any?(&:present?)

          entry(field.upcase, values.join(','), "Shelly #{field.sub('shelly_', '')} (comma-separated)")
        end
      end

      def global_optional_entries(shelly)
        return unless shelly&.connection == 'cloud'

        entry('SHELLY_CLOUD_SERVER', shelly.cloud_server,
              'Shelly Cloud server URL')
        return if shelly.auth_key.blank?

        entry('SHELLY_AUTH_KEY', shelly.auth_key,
              'Shelly Cloud authentication key')
      end

      def csv(sensors, &)
        sensors.map(&).join(',')
      end
    end
  end
end
