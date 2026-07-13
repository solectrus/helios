module Export
  class Env
    class Senec < Section
      def call
        senec = configuration.senec
        return if senec.blank?

        env.add_section('SENEC collector')
        entry('SENEC_ADAPTER', senec.adapter || 'local', 'SENEC adapter type (local or cloud)')
        if senec.adapter == 'cloud'
          cloud_entries(senec)
        else
          local_entries(senec)
        end
        entry('SENEC_INTERVAL', senec.interval || '5', 'Polling interval in seconds')
        ignore_entry
        entry('INFLUX_MEASUREMENT_SENEC', senec.measurement.presence || 'SENEC',
              'InfluxDB measurement name for SENEC')
      end

      private

      def ignore_entry
        ignore = configuration.senec_ignore
        return if ignore.blank?

        entry('SENEC_IGNORE', ignore,
              'Fields excluded from InfluxDB because another source feeds them (auto-derived)')
      end

      def cloud_entries(senec)
        entry('SENEC_USERNAME', senec.username, 'SENEC cloud username')
        entry('SENEC_PASSWORD', senec.password, 'SENEC cloud password')
        entry('SENEC_TOTP_URI', senec.totp_uri, 'SENEC TOTP URI for MFA') if senec.totp_uri.present?
        entry('SENEC_SYSTEM_ID', senec.system_id, 'SENEC system ID') if senec.system_id.present?
        return if senec.request_mode.blank?

        entry('SENEC_REQUEST_MODE', senec.request_mode,
              'Cloud request mode: minimal (default) or full (adds case_temp, application_version, current_state)')
      end

      def local_entries(senec)
        entry('SENEC_HOST', senec.host, 'SENEC device IP or hostname')
        entry('SENEC_SCHEMA', senec.schema || 'https', 'Connection protocol')
        entry('SENEC_LANGUAGE', senec.language || 'de', 'Status text language')
      end
    end
  end
end
