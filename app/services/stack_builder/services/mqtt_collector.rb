class StackBuilder
  module Services
    class MqttCollector < Base
      MAPPING_FIELDS = {
        'mqtt_topic' => 'TOPIC',
        'measurement' => 'MEASUREMENT',
        'field' => 'FIELD',
        'mqtt_payload_type' => 'TYPE',
        'mqtt_json_key' => 'JSON_KEY',
        'mqtt_formula' => 'JSON_FORMULA',
      }.freeze

      def self.service_name
        'mqtt-collector'
      end

      def self.comment
        'MQTT data collector'
      end

      def self.enabled?(configuration)
        configuration.mqtt_required?
      end

      def to_h
        {
          image: 'ghcr.io/solectrus/mqtt-collector:latest',
          environment: mqtt_environment,
          depends_on: healthy_depends_on(%i[influxdb]),
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
        %w[TZ INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET]
      end

      def explicit_vars
        [
          'INFLUX_HOST=influxdb',
          "MQTT_HOST=#{mqtt_config.mqtt_host}",
        ]
      end

      def optional_vars
        %w[mqtt_port mqtt_ssl mqtt_username mqtt_password].filter_map do |field|
          value = mqtt_config.send(field)
          "#{field.upcase}=#{value}" if value.present?
        end
      end

      def mapping_vars
        mqtt_sensors.each_with_index.flat_map do |(_, config), index|
          MAPPING_FIELDS.filter_map do |config_key, env_suffix|
            value = config[config_key]
            "MAPPING_#{index}_#{env_suffix}=#{value}" if value.present?
          end
        end
      end
    end
  end
end
