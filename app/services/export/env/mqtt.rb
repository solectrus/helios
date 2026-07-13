module Export
  class Env
    class Mqtt < Section
      OPTIONAL_ENTRIES = {
        'mqtt_ssl' => ['MQTT_SSL', 'Enable SSL for MQTT connection'],
        'mqtt_username' => ['MQTT_USERNAME', 'MQTT broker username'],
        'mqtt_password' => ['MQTT_PASSWORD', 'MQTT broker password'],
      }.freeze

      # mqtt-collector reads MQTT_PORT via `env.fetch('MQTT_PORT')` — without a
      # fallback, so an omitted variable crash-loops it. The survey field is
      # mandatory for exactly that reason; MQTT_PORT is exported unconditionally.
      def call
        mqtt = configuration.mqtt
        env.add_section('MQTT broker')
        entry('MQTT_HOST', mqtt.mqtt_host, 'MQTT broker hostname')
        entry('MQTT_PORT', mqtt.mqtt_port, 'MQTT broker port')
        OPTIONAL_ENTRIES.each do |field, (key, comment)|
          value = mqtt.send(field)
          entry(key, value, comment) if value.present?
        end
        mapping_entries
      end

      private

      def mapping_entries
        return raw_mapping_entries if configuration.collectors_only?

        sensors = configuration.sensors_with_source('mqtt')
        additional = configuration.mqtt_topics
        return if sensors.blank? && additional.empty?

        sensor_mapping_entries(sensors)
        additional_mapping_entries(additional, sensors.size)
      end

      def sensor_mapping_entries(sensors)
        sensors.each_with_index do |(sensor_name, config), index|
          env.add_comment("--- Mapping #{index} for #{sensor_name.upcase}")
          written = false
          Services::MqttCollector::MAPPING_FIELDS.each do |config_key, env_suffix|
            value = config[config_key]
            next if value.blank?

            env.add_blank_line unless written
            env["MAPPING_#{index}_#{env_suffix}"] = value
            written = true
          end
          env.add_blank_line
        end
      end

      # Numbering continues after sensor mappings so MAPPING_0..N stays one
      # contiguous range (mqtt-collector requires no gaps).
      def additional_mapping_entries(mappings, sensor_count)
        mappings.each_with_index do |mapping, offset|
          emit_raw_mapping(mapping, sensor_count + offset, suffix: ' (additional)')
        end
      end

      # Raw mappings (no sensor name) — one block per entry, numbered from 1 to
      # match how hand-maintained mqtt-collector configs look in the wild.
      def raw_mapping_entries
        mappings = configuration.mqtt_topics
        return if mappings.empty?

        mappings.each_with_index do |mapping, offset|
          emit_raw_mapping(mapping, offset + 1)
        end
      end

      def emit_raw_mapping(mapping, index, suffix: nil)
        env.add_comment("--- Mapping #{index}#{suffix}")
        written = false
        Services::MqttCollector::COLLECTORS_ONLY_MAPPING_KEYS.each do |key, env_suffix|
          value = mapping[key]
          next if value.to_s.blank?

          env.add_blank_line unless written
          env["MAPPING_#{index}_#{env_suffix}"] = value
          written = true
        end
        env.add_blank_line
      end
    end
  end
end
