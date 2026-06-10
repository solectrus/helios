module Import
  class ConfigurationImporter
    class SensorPersister
      include Helpers

      # Maps mapping env-keys (symbol) to sensor-config keys (string).
      # Sign-based splitting (measurement_positive/negative, field_positive/negative)
      # is already expanded upstream by MqttExtractor — HELIOS models 1 sensor = 1 Influx target.
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

      def initialize(sensors_data:, devices:, enabled_collectors:, mqtt_mappings:, # rubocop:disable Metrics/ParameterLists
                     excluded_sensors: [], senec_measurement: nil)
        @sensors_data = sensors_data
        @devices = devices
        @enabled_collectors = enabled_collectors
        @mqtt_mappings = mqtt_mappings
        @excluded_sensors = excluded_sensors
        @senec_measurement = senec_measurement
      end

      def persist!(config)
        @sensors_data.each_key do |sensor_name|
          source = infer_source_for_sensor(sensor_name)
          next unless source

          data = build_sensor_data(sensor_name, source)
          data['exclude_from_house_power'] = true if @excluded_sensors.include?(sensor_name)
          prefill_custom_label!(data, sensor_name)
          # Defer device pruning: sensors persist alphabetically, so a Shelly
          # sensor may land after a shadowing sensor that shares its measurement.
          config.update_sensor(sensor_name, data, prune: false)
        end

        # Prune once the full sensor set is in place, so a device still
        # consumed by a Shelly sensor survives regardless of persistence order.
        config.prune_shadowed_shelly_devices!
      end

      private

      # Pre-fill the HELIOS-only label for custom_power_* sensors with the
      # measurement, which is the user-chosen device label in the source stack
      # (e.g. "Gefrierschrank", "TERRASSE"). Saves the user from re-typing it.
      def prefill_custom_label!(data, sensor_name)
        return unless sensor_name.start_with?('custom_power_')
        return if data['name'].present?

        data['name'] = data['measurement'].presence
        data.compact!
      end

      # A concrete MQTT mapping (MAPPING_N writing into this sensor's
      # measurement:field) wins over SENEC defaults — legacy installs route
      # SENEC-default sensors through MQTT (e.g. via SENEC_IGNORE or a
      # third-party inverter), and the explicit mapping is authoritative.
      # SENEC/forecast are only credited when the actual mapping points at
      # their collector's measurement+field — otherwise a sensor that has a
      # SENEC default but a custom value (e.g. inverter_power_2 → balcony:power
      # served by a Shelly or external writer) would be misclassified.
      def infer_source_for_sensor(sensor_name)
        return 'mqtt' if mqtt_mapping_details.key?(sensor_name)
        return 'senec' if senec_provides_sensor?(sensor_name)
        return 'forecast' if forecast_provides_sensor?(sensor_name)
        return 'shelly' if shelly_device_provides_sensor?(sensor_name)

        'external'
      end

      def senec_provides_sensor?(sensor_name)
        return false unless @enabled_collectors.include?(:senec)
        return false unless SensorMappings::SENEC_DEFAULTS.key?(sensor_name)

        sensor_measurement(sensor_name) == @senec_measurement
      end

      # Forecast stays a broad check — multi-collector stacks (one per provider:
      # pvnode + solcast + forecast.solar) write to different measurements but
      # all map to the same FORECAST_DEFAULTS table, so narrowing by measurement
      # would misclassify whichever collector loses the canonical alias.
      def forecast_provides_sensor?(sensor_name)
        @enabled_collectors.include?(:forecast) && SensorMappings::FORECAST_DEFAULTS.key?(sensor_name)
      end

      def sensor_measurement(sensor_name)
        @sensors_data[sensor_name].to_s.split(':', 2).first
      end

      # A shelly device claims a sensor whose mapping is
      # `{measurement}:{power|power_a|power_b|power_c}` — `power` for the
      # device total, the per-phase fields for 3-phase Shellys (Pro/Plus 3EM).
      # Restricting to this fixed set avoids stealing unrelated sensors that
      # an mqtt-collector writes into the same measurement.
      def shelly_device_provides_sensor?(sensor_name)
        sensor_mapping = @sensors_data[sensor_name]
        return false unless sensor_mapping

        @devices.any? do |device|
          next unless device[:data].values_at(*SOURCE_FIELDS).include?('shelly')

          SHELLY_POWER_FIELDS.any? { |f| sensor_mapping == "#{device[:name]}:#{f}" }
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
        return if mapping == defaults.join(':')

        data['measurement'] = measurement
        data['field'] = field
      end

      def merge_shelly_sensor_data!(data, sensor_name)
        device = find_shelly_device_for_sensor(sensor_name)
        return unless device

        merge_shelly_mapping!(data, sensor_name)
        # Every Shelly sensor carries its own device identity (device_id/host)
        # plus optional per-device credentials — so a device that feeds a sensor
        # appears exactly once in config.yaml, on that sensor. shelly.devices is
        # left for standalone devices that no sensor consumes (see
        # ConfigurationImporter#shelly_section_data).
        merge_shelly_device_fields!(data, device)
      end

      def merge_shelly_mapping!(data, sensor_name)
        mapping = @sensors_data[sensor_name]
        return unless mapping

        measurement, field = mapping.split(':', 2)
        data['measurement'] = measurement
        data['field'] = field
      end

      # Only the genuinely per-device fields land on the sensor: the identity
      # (device_id for cloud, host for local) plus optional per-device password
      # and invert_power. Connection mode and polling interval are stack-wide
      # and stay on the shelly section — the .env export and the sensor survey
      # read them from there, never per sensor.
      def merge_shelly_device_fields!(data, device)
        device_data = device[:data]
        data['shelly_host'] = device_data['shelly_host']
        data['shelly_password'] = device_data['shelly_password']
        data['shelly_device_id'] = device_data['shelly_device_id']
        data['shelly_invert_power'] = device_data['shelly_invert_power']
      end

      def find_shelly_device_for_sensor(sensor_name)
        mapping = @sensors_data[sensor_name]
        return nil unless mapping

        @devices.find do |device|
          next unless device[:data].values_at(*SOURCE_FIELDS).include?('shelly')

          mapping.start_with?("#{device[:name]}:")
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
