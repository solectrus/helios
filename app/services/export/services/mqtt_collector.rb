module Export
  module Services
    class MqttCollector < Base
      MAPPING_FIELDS = {
        'mqtt_topic' => 'TOPIC',
        'measurement' => 'MEASUREMENT',
        'field' => 'FIELD',
        'mqtt_payload_type' => 'TYPE',
        'mqtt_json_key' => 'JSON_KEY',
        'mqtt_json_path' => 'JSON_PATH',
        'mqtt_json_formula' => 'JSON_FORMULA',
        'mqtt_formula' => 'FORMULA',
        'mqtt_min' => 'MIN',
        'mqtt_max' => 'MAX',
        'mqtt_null_to_zero' => 'NULL_TO_ZERO',
      }.freeze

      def self.service_name
        'mqtt-collector'
      end

      def self.comment
        'MQTT Collector — Receives sensor data via MQTT protocol'
      end

      def self.enabled?(configuration)
        configuration.mqtt_required?
      end

      def to_h
        {
          image: 'ghcr.io/solectrus/mqtt-collector:latest',
          environment: mqtt_environment,
          depends_on: healthy_depends_on([collector_influx_target]),
          restart: 'unless-stopped',
        }
      end

      private

      def mqtt_sensors
        @mqtt_sensors ||= configuration.sensors_with_source('mqtt')
      end

      def mqtt_config
        configuration.mqtt
      end

      def mqtt_environment
        passthrough_vars + explicit_vars + optional_vars + mapping_vars
      end

      def passthrough_vars
        %w[TZ INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET MQTT_HOST]
      end

      def optional_vars
        %w[mqtt_port mqtt_ssl mqtt_username mqtt_password].filter_map do |field|
          field.upcase if mqtt_config.send(field).present?
        end
      end

      def mapping_vars
        mqtt_sensors.each_with_index.flat_map do |(_, config), index|
          MAPPING_FIELDS.filter_map do |config_key, env_suffix|
            "MAPPING_#{index}_#{env_suffix}" if config[config_key].present?
          end
        end
      end
    end
  end
end
