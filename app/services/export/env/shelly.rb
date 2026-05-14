module Export
  class Env
    class Shelly < Section
      def call
        return devices_section if Array(configuration.shelly&.devices).any?

        sensors_section
      end

      private

      def sensors_section
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

      def host_entry(sensors, shelly)
        return if shelly&.connection == 'cloud'

        entry('SHELLY_HOST', csv(sensors) { |_, config| config['shelly_host'] },
              'Shelly device hostnames (comma-separated)')
      end

      # CSV-mode .env block: one canonical shelly-collector consumes CSVs of
      # SHELLY_HOST / INFLUX_MEASUREMENT (plus optional per-device variants).
      # Used for both collectors-only stacks and full-mode multi-device setups
      # — the per-sensor pathway above only applies to single-device stacks
      # where each `source: shelly` sensor carries its own shelly_host.
      def devices_section
        shelly = configuration.shelly
        devices = Array(shelly&.devices)
        return if devices.empty?

        env.add_section('Shelly collector')
        entry('SHELLY_INTERVAL', shelly.interval || '5', 'Polling interval in seconds')
        devices_id_entries(devices, shelly)
        devices_extra_entries(devices, shelly)
        global_optional_entries(shelly)
      end

      def devices_id_entries(devices, shelly)
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

      def devices_extra_entries(devices, shelly)
        optional_entry('INFLUX_MODE', shelly.mode, 'InfluxDB write mode (default or essential)')
        optional_entry('INFLUX_POWER_DATA_TYPE', shelly.power_data_type,
                       'Data type for power values in InfluxDB (Float or Integer)')
        password_entry(devices, shelly)
        invert_power_entry(devices)
      end

      # Per-device passwords win over the global one — the collector reads
      # SHELLY_PASSWORD as CSV when the values per device differ. If no device
      # carries its own password we fall back to the global default.
      def password_entry(devices, shelly)
        if devices.any? { |d| d['password'].present? }
          csv = devices.map { |d| d['password'].to_s }.join(',')
          entry('SHELLY_PASSWORD', csv, 'Shelly device passwords (comma-separated)')
        else
          optional_entry('SHELLY_PASSWORD', shelly.password, 'Shelly device password')
        end
      end

      def invert_power_entry(devices)
        return unless devices.any? { |d| d['invert_power'] }

        csv = devices.map { |d| d['invert_power'] ? 'true' : '' }.join(',')
        entry('SHELLY_INVERT_POWER', csv,
              'Invert reported power per device (comma-separated)')
      end

      def optional_entries(sensors, shelly)
        per_sensor_optional_entries(sensors)
        influx_optional_entries(shelly)
        global_optional_entries(shelly)
      end

      def influx_optional_entries(shelly)
        optional_entry('INFLUX_MODE', shelly&.mode, 'InfluxDB write mode (default or essential)')
        optional_entry('INFLUX_POWER_DATA_TYPE', shelly&.power_data_type,
                       'Data type for power values in InfluxDB (Float or Integer)')
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
