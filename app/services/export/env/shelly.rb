module Export
  class Env
    class Shelly < Section
      def call
        devices = configuration.shelly_collector_devices
        return if devices.empty?

        env.add_section('Shelly collector')
        entry('SHELLY_INTERVAL', shelly&.interval || '5', 'Polling interval in seconds')
        identifier_entry(devices)
        entry('INFLUX_MEASUREMENT', present_csv(devices, 'measurement'),
              'InfluxDB measurement names (comma-separated)')
        influx_optional_entries
        password_entry(devices)
        invert_power_entry(devices)
        cloud_entries
      end

      private

      def shelly
        configuration.shelly
      end

      # Cloud stacks address devices by SHELLY_DEVICE_ID, local stacks by
      # SHELLY_HOST — the collector reads either as a comma-separated list.
      def identifier_entry(devices)
        if shelly&.connection == 'cloud'
          entry('SHELLY_DEVICE_ID', present_csv(devices, 'device_id'),
                'Shelly cloud device IDs (comma-separated)')
        else
          entry('SHELLY_HOST', present_csv(devices, 'host'),
                'Shelly device hostnames (comma-separated)')
        end
      end

      def influx_optional_entries
        optional_entry('INFLUX_MODE', shelly&.mode, 'InfluxDB write mode (default or essential)')
        optional_entry('INFLUX_POWER_DATA_TYPE', shelly&.power_data_type,
                       'Data type for power values in InfluxDB (Float or Integer)')
      end

      # Per-device passwords win over the global one — the collector reads
      # SHELLY_PASSWORD as a comma-separated list when the values per device
      # differ. With no per-device password we fall back to the global default.
      def password_entry(devices)
        if devices.any? { |d| d['password'].present? }
          entry('SHELLY_PASSWORD', devices.map { |d| d['password'].to_s }.join(','),
                'Shelly device passwords (comma-separated)')
        else
          optional_entry('SHELLY_PASSWORD', shelly&.password, 'Shelly device password')
        end
      end

      def invert_power_entry(devices)
        return unless devices.any? { |d| d['invert_power'] }

        csv = devices.map { |d| d['invert_power'] ? 'true' : '' }.join(',')
        entry('SHELLY_INVERT_POWER', csv,
              'Invert reported power per device (comma-separated)')
      end

      def cloud_entries
        return unless shelly&.connection == 'cloud'

        entry('SHELLY_CLOUD_SERVER', shelly.cloud_server, 'Shelly Cloud server URL')
        return if shelly.auth_key.blank?

        entry('SHELLY_AUTH_KEY', shelly.auth_key, 'Shelly Cloud authentication key')
      end

      # Identifier and measurement lists drop blanks independently (matching the
      # historical devices export): a ghost device with a host but no
      # measurement still contributes its host, so the two lists can differ in
      # length — faithfully reproducing the donor's setup. Password/invert lists
      # stay positional (see their entries) and are not built through here.
      def present_csv(devices, field)
        devices.filter_map { |d| d[field].presence }.join(',')
      end
    end
  end
end
