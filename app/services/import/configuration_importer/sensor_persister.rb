module Import
  class ConfigurationImporter
    class SensorPersister
      include Helpers

      # Maps mapping env-keys (symbol) to sensor-config keys (string).
      # Sign-based splitting (measurement_positive/negative, field_positive/negative)
      # is already expanded upstream by MqttExtractor — Helios models 1 sensor = 1 Influx target.
      MQTT_MAPPING_TO_SENSOR_KEY = {
        measurement: 'measurement',
        field: 'field',
        topic: 'mqtt_topic',
        type: 'mqtt_payload_type',
        json_key: 'mqtt_json_key',
        json_path: 'mqtt_json_path',
        json_formula: 'mqtt_json_formula',
        formula: 'mqtt_formula',
        min: 'mqtt_min',
        max: 'mqtt_max',
        null_to_zero: 'mqtt_null_to_zero',
      }.freeze

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

          config.update_sensor(sensor_name, build_sensor_data(sensor_name, source))
        end
      end

      private

      def infer_source_for_sensor(sensor_name)
        return 'senec' if SensorMappings::SENEC_DEFAULTS.key?(sensor_name) && @senec_enabled
        return 'forecast' if SensorMappings::FORECAST_DEFAULTS.key?(sensor_name)
        return 'shelly' if device_provides_sensor?(sensor_name, 'shelly')
        return 'mqtt' if device_provides_sensor?(sensor_name, 'mqtt')

        'external'
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
        else merge_raw_mapping!(data, sensor_name)
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
        data['shelly_connection'] = device_data['shelly_device_id'].present? ? 'cloud' : 'local'
        data['shelly_host'] = device_data['shelly_host']
        data['shelly_interval'] = device_data['shelly_interval']
        data['shelly_password'] = device_data['shelly_password']
        data['shelly_device_id'] = device_data['shelly_device_id']
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

      def merge_raw_mapping!(data, sensor_name)
        mapping = @sensors_data[sensor_name]
        return unless mapping

        measurement, field = mapping.split(':', 2)
        return unless measurement.present? && field.present?

        data['measurement'] = measurement
        data['field'] = field
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

          details[sensor_name] = MQTT_MAPPING_TO_SENSOR_KEY
                                 .to_h { |src, dst| [dst, mapping[src]] }
                                 .compact
        end
      end
    end
  end
end
