class ConfigurationImporter
  class ShellyExtractor
    include Helpers

    OPTIONAL_FIELDS = {
      passwords: 'shelly_password',
      cloud_servers: 'shelly_cloud_server',
      auth_keys: 'shelly_auth_key',
      device_ids: 'shelly_device_id',
      invert_powers: 'shelly_invert_power',
    }.freeze

    def initialize(reader, sensors_data)
      @reader = reader
      @sensors_data = sensors_data
    end

    def enabled?
      @reader.services.key?('shelly-collector')
    end

    def section_data
      return unless enabled?

      shelly_env = service_env('shelly-collector')
      connection = shelly_env['SHELLY_CLOUD_SERVER'].present? ? 'cloud' : 'local'
      intervals = csv_split(shelly_env['SHELLY_INTERVAL'])
      interval = intervals.first.presence || '5'

      {
        'connection' => connection,
        'interval' => interval,
      }
    end

    def device_data
      parsed = parse_csv_fields
      build_devices(parsed)
    end

    private

    def parse_csv_fields
      shelly_env = service_env('shelly-collector')
      {
        hosts: csv_split(shelly_env['SHELLY_HOST']),
        intervals: csv_split(shelly_env['SHELLY_INTERVAL']),
        measurements: csv_split(shelly_env['INFLUX_MEASUREMENT']),
        passwords: csv_split(shelly_env['SHELLY_PASSWORD']),
        cloud_servers: csv_split(shelly_env['SHELLY_CLOUD_SERVER']),
        auth_keys: csv_split(shelly_env['SHELLY_AUTH_KEY']),
        device_ids: csv_split(shelly_env['SHELLY_DEVICE_ID']),
        invert_powers: csv_split(shelly_env['SHELLY_INVERT_POWER']),
      }
    end

    def build_devices(parsed)
      parsed[:hosts].each_with_index.filter_map do |host, i|
        next if host.blank?

        build_single_device(i, parsed)
      end
    end

    def build_single_device(index, parsed)
      name = parsed[:measurements][index].presence || "Shelly#{index + 1}"
      device_type = infer_device_type(name)
      data = device_config(device_type, index, parsed)

      { type: device_type, name:, data: }
    end

    def device_config(device_type, index, parsed)
      field = DATA_SOURCE_FIELDS.fetch(device_type, 'data_source')
      data = {
        field => 'shelly',
        'shelly_host' => parsed[:hosts][index],
        'shelly_interval' => parsed[:intervals][index].presence || '5',
      }
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
