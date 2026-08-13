module Export
  module Services
    class MqttCollector < Base
      def self.service_name
        'mqtt-collector'
      end

      def self.config_keys
        ['mqtt']
      end

      def self.comment
        'MQTT Collector — Receives sensor data via MQTT protocol'
      end

      # Standalone topics (full mode) keep the collector running even when
      # no HELIOS sensor consumes MQTT — drop the gate and the collector
      # stops ingesting, leaving a gap in InfluxDB.
      #
      # Without an mqtt_host the collector would restart-loop trying to
      # reach an empty broker, so we skip it (mappings stay in config.yaml,
      # the section reappears once the host is filled in via the UI).
      def self.enabled?(configuration)
        return false if configuration.dashboard_only?
        return false if configuration.mqtt&.mqtt_host.blank?

        configuration.mqtt_required? || configuration.mqtt_topics.any?
      end

      def to_h
        {
          image: mqtt_config&.image.presence || DockerImages.current(:MQTT_COLLECTOR),
          environment: mqtt_environment,
          depends_on: collector_depends_on,
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
        return collectors_only_environment if configuration.collectors_only?

        passthrough_vars + explicit_vars + optional_vars + mapping_vars
      end

      # In collectors_only mode the mappings are raw (no sensor names) —
      # numbering starts at 1 so the output matches how existing mqtt-collector
      # installations typically look.
      def collectors_only_environment
        vars = ConfigSchema::INFLUXDB_EXTERNAL_ENV_KEYS.dup
        vars += %w[TZ INFLUX_ORG INFLUX_BUCKET MQTT_HOST MQTT_PORT]
        vars << influx_token_write_var
        vars += optional_vars
        vars + raw_mapping_vars
      end

      def raw_mapping_vars
        raw_mapping_var_names(start_index: 1)
      end

      def passthrough_vars
        %w[TZ INFLUX_ORG INFLUX_BUCKET MQTT_HOST MQTT_PORT]
      end

      # MQTT_PORT is not among these: Export::Env::Mqtt always emits it (with
      # a default), because the collector has no fallback for it.
      def optional_vars
        %w[mqtt_ssl mqtt_username mqtt_password].filter_map do |field|
          field.upcase if mqtt_config.send(field).present?
        end
      end

      def mapping_vars
        sensor_mapping_vars + additional_mapping_vars
      end

      def sensor_mapping_vars
        mqtt_sensors.each_with_index.flat_map do |(_, config), index|
          ConfigSchema::MQTT_MAPPING_SENSOR_KEYS.filter_map do |mapping_field, sensor_key|
            "MAPPING_#{index}_#{mapping_field.upcase}" if config[sensor_key].present?
          end
        end
      end

      def additional_mapping_vars
        raw_mapping_var_names(start_index: mqtt_sensors.size)
      end

      def raw_mapping_var_names(start_index:)
        configuration.mqtt_topics.each_with_index.flat_map do |mapping, offset|
          index = start_index + offset
          ConfigSchema::MQTT_MAPPING_FIELDS.filter_map do |mapping_field|
            "MAPPING_#{index}_#{mapping_field.upcase}" if mapping[mapping_field].to_s.present?
          end
        end
      end
    end
  end
end
