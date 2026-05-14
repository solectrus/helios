module Import
  class ConfigurationImporter
    class ShellyExtractor
      include Helpers

      SHELLY_IMAGE_PREFIX = 'ghcr.io/solectrus/shelly-collector'.freeze

      OPTIONAL_FIELDS = {
        passwords: 'shelly_password',
        device_ids: 'shelly_device_id',
        invert_powers: 'shelly_invert_power',
      }.freeze

      def initialize(reader, sensors_data)
        @reader = reader
        @sensors_data = sensors_data
      end

      def self.shelly_image?(image)
        image.to_s.start_with?(SHELLY_IMAGE_PREFIX)
      end

      def enabled?
        shelly_service_names.any?
      end

      # True when the donor stack carries more than one Shelly device — either
      # via a single CSV-valued shelly-collector (`SHELLY_HOST=h1,h2,...`) or
      # via several shelly-collector-<suffix> services, each with its own
      # device. Drives the CSV-mode export path: HELIOS rolls them up into a
      # single canonical shelly-collector container with comma-separated
      # SHELLY_HOST / INFLUX_MEASUREMENT, and surfaces the device list as
      # `shelly.devices` in `config.yaml` as the round-trip source of truth.
      def multi_device?
        return false unless enabled?

        raw_devices.size > 1
      end

      # Names of all services that use the shelly-collector image.
      # A stack may carry either a single service (typically "shelly-collector",
      # multi-device via CSV-valued env vars) or several single-device services
      # like "shelly-collector-fridge", "shelly-collector-dishwasher", ...
      def shelly_service_names
        @shelly_service_names ||= @reader.services.filter_map do |name, service|
          name if self.class.shelly_image?(service['image'])
        end
      end

      def section_data
        return unless enabled?

        build_section_data(service_env(shelly_service_names.first))
      end

      def device_data
        shelly_service_names.flat_map { |name| devices_for_service(name) }
      end

      # Raw device list: one hash per Shelly device, aggregated across every
      # shelly-collector service in the stack. Local-mode uses SHELLY_HOST and
      # a "host" field; cloud-mode uses SHELLY_DEVICE_ID and a "device_id"
      # field. The measurement aligns by index with the comma-separated
      # INFLUX_MEASUREMENT list the collector consumes. In local-mode, names
      # are derived from ${SHELLY_HOST_<NAME>} references in the raw compose;
      # cloud-mode falls back to a sequential placeholder. Per-device password
      # and invert_power flags are picked up from their CSV env vars when
      # present.
      #
      # Two donor topologies converge here:
      #   - one shelly-collector with CSV-valued SHELLY_HOST/INFLUX_MEASUREMENT
      #     (legacy multi-device-per-service, e.g. collectors_only fixture)
      #   - multiple shelly-collector-<suffix> services, one device each (e.g.
      #     user18 with -tv/-gsa/-oven/...). Each service contributes its own
      #     row to the same flat list.
      def raw_devices
        return [] unless enabled?

        shelly_service_names.flat_map { |name| raw_devices_for_service(name) }
      end

      def raw_devices_for_service(service_name)
        ctx = raw_devices_context(service_name)
        offset = device_offset_for(service_name)
        ctx[:identifiers].each_with_index.map do |id, i|
          {
            'name' => ctx[:names][i] || "device#{offset + i + 1}",
            ctx[:field] => id,
            'measurement' => ctx[:measurements][i],
            'password' => ctx[:passwords][i],
            'invert_power' => ctx[:invert_powers][i],
          }.compact
        end
      end

      def raw_devices_context(service_name)
        env = service_env(service_name)
        cloud = env['SHELLY_CLOUD_SERVER'].present?
        identifiers = csv_split(env[cloud ? 'SHELLY_DEVICE_ID' : 'SHELLY_HOST'])
        raw_env = raw_compose_env(service_name)
        names = shelly_interpolated_names(raw_env, cloud ? 'SHELLY_DEVICE_ID' : 'SHELLY_HOST', identifiers.size)
        {
          identifiers: identifiers,
          measurements: csv_split(env['INFLUX_MEASUREMENT']),
          names: names,
          field: cloud ? 'device_id' : 'host',
          passwords: per_device_passwords(env, identifiers.size),
          invert_powers: invert_power_flags(env, identifiers.size),
        }
      end

      # Running device count before the given service — used as the base for
      # the `device{N}` fallback name so multi-service stacks without
      # ${SHELLY_HOST_<NAME>} hints don't collapse onto the same key.
      def device_offset_for(service_name)
        @device_offsets ||= compute_device_offsets
        @device_offsets[service_name] || 0
      end

      def compute_device_offsets
        offsets = {}
        running = 0
        shelly_service_names.each do |name|
          offsets[name] = running
          env = service_env(name)
          running += csv_split(env['SHELLY_HOST'].presence || env['SHELLY_DEVICE_ID']).size
        end
        offsets
      end

      # Per-device passwords are attributed when at least one slot carries a
      # value and the CSV is not uniformly shared (handled by
      # `shared_password`). A donor with `SHELLY_PASSWORD=,,secret,,` means
      # only device index 2 carries a password — re-emitting it as a single
      # `SHELLY_PASSWORD=secret` would silently grant the credential to every
      # device, so we keep the index-aligned form instead.
      def per_device_passwords(env, size)
        return Array.new(size) if shared_password_value(env).present?

        passwords = csv_split(env['SHELLY_PASSWORD'])
        Array.new(size) { |i| passwords[i].presence }
      end

      def invert_power_flags(env, size)
        flags = csv_split(env['SHELLY_INVERT_POWER'])
        Array.new(size) { |i| flags[i].to_s.casecmp('true').zero? || nil }
      end

      # Shared SHELLY_PASSWORD when every device carries the same non-empty
      # value (the common case for a home full of identically-configured
      # plugs). Mixed per-device passwords — including the partial form where
      # some slots are blank — stay device-side via `per_device_passwords`.
      def shared_password
        return nil unless enabled?

        shared_password_value(service_env(shelly_service_names.first))
      end

      def shared_password_value(env)
        passwords = csv_split(env['SHELLY_PASSWORD'])
        return nil if passwords.empty?
        return nil unless passwords.all?(&:present?)
        return nil unless passwords.uniq.size == 1

        passwords.first
      end

      private

      # Names from ${SHELLY_HOST_<NAME>} / ${SHELLY_DEVICE_ID_<NAME>}
      # references in the *raw* compose environment list (pre-interpolation).
      # Falls back to nil entries when the stack used a literal CSV instead;
      # the caller turns those into sequential `deviceN` placeholders.
      def shelly_interpolated_names(compose_env, env_key, expected_size)
        prefix = "#{env_key}="
        entry = compose_env.find { |e| e.is_a?(String) && e.start_with?(prefix) }
        return Array.new(expected_size) unless entry

        value = entry.split('=', 2).last.to_s
        csv_split(value).map do |piece|
          match = piece.match(/\A\$\{#{env_key}_([A-Z0-9_]+)\}\z/)
          match && match[1].downcase
        end
      end

      def raw_compose_env(service_name)
        Array(@reader.raw_compose.dig('services', service_name, 'environment'))
      end

      def devices_for_service(service_name)
        parsed = parse_service(service_name)
        parsed[:hosts_or_ids].each_with_index.filter_map do |_, index|
          build_single_device(index, parsed)
        end
      end

      # Normalize the env-vars of one shelly-collector service into index-aligned
      # arrays. Works for both CSV-valued (legacy multi-device) and scalar
      # (one-device-per-service) setups.
      def parse_service(service_name)
        env = service_env(service_name)
        hosts = csv_split(env['SHELLY_HOST'])
        device_ids = csv_split(env['SHELLY_DEVICE_ID'])
        measurements = csv_split(env['INFLUX_MEASUREMENT'])

        {
          hosts_or_ids: hosts.any?(&:present?) ? hosts : device_ids,
          hosts: hosts,
          measurements: measurements,
          passwords: csv_split(env['SHELLY_PASSWORD']),
          device_ids: device_ids,
          invert_powers: csv_split(env['SHELLY_INVERT_POWER']),
          interval: env['SHELLY_INTERVAL'],
        }
      end

      def build_section_data(shelly_env)
        connection = shelly_env['SHELLY_CLOUD_SERVER'].present? ? 'cloud' : 'local'

        data = {
          'connection' => connection,
          'interval' => min_interval,
          'mode' => shelly_env['INFLUX_MODE'],
          'power_data_type' => shelly_env['INFLUX_POWER_DATA_TYPE'],
        }
        if connection == 'cloud'
          data['cloud_server'] = shelly_env['SHELLY_CLOUD_SERVER']&.split(',')&.first
          data['auth_key'] = shelly_env['SHELLY_AUTH_KEY']&.split(',')&.first
        end
        data.compact
      end

      # Shelly has a single UI field for the global interval; when several
      # per-device services define their own, we pick the shortest so the UI
      # default reflects the most aggressive polling already in use.
      def min_interval
        intervals = shelly_service_names.filter_map do |name|
          service_env(name)['SHELLY_INTERVAL'].presence&.to_i
        end
        intervals.min&.to_s
      end

      def build_single_device(index, parsed)
        name = parsed[:measurements][index].presence || "Shelly#{index + 1}"
        device_type = infer_device_type(name)
        data = device_config(device_type, index, parsed)

        { type: device_type, name:, data: }
      end

      def device_config(device_type, index, parsed)
        field = DATA_SOURCE_FIELDS.fetch(device_type, 'data_source')
        data = { field => 'shelly' }
        data['shelly_host'] = parsed[:hosts][index] if parsed[:hosts][index].present?
        data['shelly_interval'] = parsed[:interval] if parsed[:interval].present?
        apply_optional_fields(data, index, parsed)
        data
      end

      def apply_optional_fields(data, index, parsed)
        OPTIONAL_FIELDS.each do |key, field|
          value = parsed[key][index]
          data[field] = value if value.present?
        end
      end

      def infer_device_type(measurement_name)
        mappings = SHELLY_POWER_FIELDS.map { |f| "#{measurement_name}:#{f}" }
        return 'inverter' if inverter_sensor?(mappings)
        return 'heatpump' if mappings.include?(@sensors_data['heatpump_power'])
        return 'wallbox' if mappings.include?(@sensors_data['wallbox_power'])

        'consumer'
      end

      def inverter_sensor?(mappings)
        %w[inverter_power inverter_power_1 inverter_power_2
           inverter_power_3 inverter_power_4 inverter_power_5].any? do |key|
          mappings.include?(@sensors_data[key])
        end
      end
    end
  end
end
