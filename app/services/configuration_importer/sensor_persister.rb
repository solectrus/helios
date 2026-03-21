class ConfigurationImporter
  class SensorPersister
    include Helpers

    def initialize(sensors_data:, devices:, senec_enabled:, mqtt_mappings:)
      @sensors_data = sensors_data
      @devices = devices
      @senec_enabled = senec_enabled
      @mqtt_mappings = mqtt_mappings
    end

    def persist!(config)
      @sensors_data.each_key do |sensor_name|
        source = infer_source_for_sensor(sensor_name)
        next unless source

        sensor_data = build_sensor_data(sensor_name, source)
        config.update_sensor(sensor_name, sensor_data)
      end
    end

    private

    def infer_source_for_sensor(sensor_name)
      return 'senec' if SensorMappings::SENEC_DEFAULTS.key?(sensor_name) && @senec_enabled
      return 'forecast' if SensorMappings::FORECAST_DEFAULTS.key?(sensor_name)
      return 'shelly' if device_provides_sensor?(sensor_name, 'shelly')
      return 'mqtt' if device_provides_sensor?(sensor_name, 'mqtt')

      'smart_home'
    end

    def device_provides_sensor?(sensor_name, source_type)
      source_fields = %w[data_source wallbox_vendor heatpump_access battery_vendor]

      @devices.any? do |device|
        next unless device[:data].values_at(*source_fields).include?(source_type)

        sensor_mapping = @sensors_data[sensor_name]
        next unless sensor_mapping

        sensor_mapping.start_with?("#{device[:name]}:")
      end
    end

    def build_sensor_data(sensor_name, source)
      data = { 'source' => source }

      case source
      when 'senec' then merge_sensor_overrides!(data, sensor_name, SensorMappings::SENEC_DEFAULTS)
      when 'forecast' then merge_sensor_overrides!(data, sensor_name, SensorMappings::FORECAST_DEFAULTS)
      when 'shelly' then merge_shelly_sensor_data!(data, sensor_name)
      when 'mqtt' then merge_mqtt_sensor_data!(data, sensor_name)
      end

      data.compact
    end

    def merge_sensor_overrides!(data, sensor_name, defaults_hash)
      mapping = @sensors_data[sensor_name]
      return unless mapping

      defaults = defaults_hash[sensor_name]
      return unless defaults

      measurement, field = mapping.split(':', 2)
      default_mapping = "#{defaults[:measurement]}:#{defaults[:field]}"
      return if mapping == default_mapping

      data['measurement'] = measurement
      data['field'] = field
    end

    def merge_shelly_sensor_data!(data, sensor_name)
      device = find_shelly_device_for_sensor(sensor_name)
      return unless device

      merge_shelly_mapping!(data, sensor_name)
      merge_shelly_device_fields!(data, device)
    end

    def merge_shelly_mapping!(data, sensor_name)
      mapping = @sensors_data[sensor_name]
      return unless mapping

      measurement, field = mapping.split(':', 2)
      data['measurement'] = measurement
      data['field'] = field
    end

    def merge_shelly_device_fields!(data, device)
      device_data = device[:data]
      data['name'] = device_data['name'] || device[:name]
      data['shelly_connection'] = device_data['shelly_cloud_server'].present? ? 'cloud' : 'local'
      data['shelly_host'] = device_data['shelly_host']
      data['shelly_interval'] = device_data['shelly_interval']
      data['shelly_password'] = device_data['shelly_password']
      data['exclude_from_house_power'] = true if device_data['exclude_from_house_power']
    end

    def find_shelly_device_for_sensor(sensor_name)
      mapping = @sensors_data[sensor_name]
      return nil unless mapping

      @devices.find do |device|
        data = device[:data]
        is_shelly = data.values_at('data_source', 'wallbox_vendor', 'heatpump_access',
                                   'battery_vendor').include?('shelly')
        is_shelly && mapping.start_with?("#{device[:name]}:")
      end
    end

    def merge_mqtt_sensor_data!(data, sensor_name)
      details = mqtt_mapping_details[sensor_name]
      return unless details

      data.merge!(details)
    end

    # Build a per-sensor lookup of MQTT mapping details from the mqtt-collector env
    def mqtt_mapping_details
      @mqtt_mapping_details ||= build_mqtt_mapping_details
    end

    def build_mqtt_mapping_details
      @mqtt_mappings.each_with_object({}) do |mapping, details|
        candidate = "#{mapping[:measurement]}:#{mapping[:field]}"
        sensor_name = find_sensor_for_candidate(@sensors_data, candidate)
        next unless sensor_name

        details[sensor_name] = {
          'measurement' => mapping[:measurement],
          'field' => mapping[:field],
          'mqtt_topic' => mapping[:topic],
          'mqtt_payload_type' => mapping[:type],
          'mqtt_json_key' => mapping[:json_key],
          'mqtt_formula' => mapping[:json_formula],
        }.compact
      end
    end
  end
end
