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
        return false if configuration.dashboard_only?

        configuration.mqtt_required? || (configuration.collectors_only? && collectors_only_enabled?(configuration))
      end

      def self.collectors_only_enabled?(configuration)
        Array(configuration.mqtt&.mappings).any?
      end

      def to_h
        {
          image: mqtt_config&.image.presence || 'ghcr.io/solectrus/mqtt-collector:latest',
          environment: mqtt_environment,
          depends_on: collector_depends_on,
          restart: 'unless-stopped',
        }
      end

      # Keys (in `mqtt.mappings`) that correspond to the MAPPING_N_* env var
      # suffixes the collector consumes. Order defines the order we emit.
      COLLECTORS_ONLY_MAPPING_KEYS = {
        'topic' => 'TOPIC',
        'measurement' => 'MEASUREMENT',
        'field' => 'FIELD',
        'type' => 'TYPE',
        'json_key' => 'JSON_KEY',
        'json_path' => 'JSON_PATH',
        'json_formula' => 'JSON_FORMULA',
        'formula' => 'FORMULA',
        'min' => 'MIN',
        'max' => 'MAX',
        'null_to_zero' => 'NULL_TO_ZERO',
      }.freeze

      private

      def mqtt_sensors
        @mqtt_sensors ||= configuration.sensors_with_source('mqtt')
      end

      def mqtt_config
        configuration.mqtt
      end

      def mqtt_environment
        return collectors_only_environment if configuration.collectors_only?

        passthrough_vars + explicit_vars + optional_vars + mapping_vars
      end

      # In collectors_only mode the mappings are raw (no sensor names) —
      # numbering starts at 1 so the output matches how existing mqtt-collector
      # installations typically look.
      def collectors_only_environment
        vars = ConfigSchema::INFLUXDB_EXTERNAL_ENV_KEYS.dup
        vars += %w[TZ INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET MQTT_HOST]
        vars += optional_vars
        vars + raw_mapping_vars
      end

      def raw_mapping_vars
        Array(mqtt_config.mappings).each_with_index.flat_map do |mapping, index|
          COLLECTORS_ONLY_MAPPING_KEYS.filter_map do |key, env_suffix|
            "MAPPING_#{index + 1}_#{env_suffix}" if mapping[key].to_s.present?
          end
        end
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
