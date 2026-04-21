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

      private

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

        data = { 'connection' => connection, 'interval' => min_interval }
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
        mapping = "#{measurement_name}:power"
        return 'inverter' if inverter_sensor?(mapping)
        return 'heatpump' if @sensors_data['heatpump_power'] == mapping
        return 'wallbox' if @sensors_data['wallbox_power'] == mapping

        'consumer'
      end

      def inverter_sensor?(mapping)
        %w[inverter_power inverter_power_1 inverter_power_2
           inverter_power_3 inverter_power_4 inverter_power_5].any? do |key|
          @sensors_data[key] == mapping
        end
      end
    end
  end
end
