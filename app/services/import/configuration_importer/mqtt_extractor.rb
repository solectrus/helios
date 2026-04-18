module Import
  class ConfigurationImporter
    class MqttExtractor
      include Helpers

      MAPPING_FIELDS = %i[
        topic measurement field
        measurement_positive measurement_negative field_positive field_negative
        json_key json_path json_formula formula
        type min max null_to_zero
      ].freeze

      SPLIT_FIELDS = %i[
        measurement_positive measurement_negative field_positive field_negative
      ].freeze

      # Maps sensor names to the device type they indicate.
      # Sensors not listed here are either shared (forecast)
      # or handled via pattern matching (inverter_power_*, custom_power_*).
      SENSOR_DEVICE_TYPE = {
        'wallbox_power' => 'wallbox',
        'wallbox_car_connected' => 'wallbox',
        'car_battery_soc' => 'car',
        'heatpump_power' => 'heatpump',
        'heatpump_heating_power' => 'heatpump',
        'heatpump_status' => 'heatpump',
        'heatpump_tank_temp' => 'heatpump',
        'heatpump_tank_temp_setpoint' => 'heatpump',
        'battery_soc' => 'battery',
        'battery_charging_power' => 'battery',
        'battery_discharging_power' => 'battery',
        'case_temp' => 'inverter',
        'system_status' => 'inverter',
        'system_status_ok' => 'inverter',
        'grid_export_limit' => 'inverter',
        'house_power' => 'inverter',
        'grid_import_power' => 'inverter',
        'grid_export_power' => 'inverter',
        'outdoor_temp' => 'inverter',
      }.freeze

      # Maps sensor names to the mqtt_topic_* field they should be stored in.
      # The primary sensor for each device type maps to plain 'mqtt_topic'.
      SENSOR_TOPIC_FIELDS = {
        'heatpump_power' => 'mqtt_topic',
        'heatpump_heating_power' => 'mqtt_topic_heating_power',
        'heatpump_tank_temp' => 'mqtt_topic_tank_temp',
        'heatpump_tank_temp_setpoint' => 'mqtt_topic_tank_temp_setpoint',
        'heatpump_status' => 'mqtt_topic_heatpump_status',
        'outdoor_temp' => 'mqtt_topic_outdoor_temp',
        'wallbox_power' => 'mqtt_topic',
        'wallbox_car_connected' => 'mqtt_topic_car_connected',
        'car_battery_soc' => 'mqtt_topic',
      }.freeze

      def initialize(reader, sensors_data)
        @reader = reader
        @sensors_data = sensors_data
      end

      def enabled?
        @reader.services.key?('mqtt-collector')
      end

      def broker_data
        return unless enabled?

        mqtt_env = service_env('mqtt-collector')
        {
          'mqtt_host' => mqtt_env['MQTT_HOST'],
          'mqtt_port' => mqtt_env['MQTT_PORT'],
          'mqtt_ssl' => mqtt_env['MQTT_SSL'],
          'mqtt_username' => mqtt_env['MQTT_USERNAME'],
          'mqtt_password' => mqtt_env['MQTT_PASSWORD'],
        }.compact.presence
      end

      def device_data
        build_devices(mappings)
      end

      def mappings
        @mappings ||= parse_mappings(service_env('mqtt-collector'))
      end

      private

      def parse_mappings(mqtt_env)
        raw = mapping_indices(mqtt_env).map do |i|
          MAPPING_FIELDS.index_with { |f| mqtt_env["MAPPING_#{i}_#{f.upcase}"] }.compact
        end
        raw.flat_map { |m| expand_sign_split(m) }
      end

      # mqtt-collector's sign-based splitting (MEASUREMENT_POSITIVE/NEGATIVE + FIELD_POSITIVE/NEGATIVE)
      # writes one topic into two Influx locations. Helios models one sensor = one Influx target,
      # so we expand such mappings into two sensors, each with a sign-filter formula that keeps
      # only the matching half of the value.
      def expand_sign_split(mapping)
        return [mapping] if SPLIT_FIELDS.none? { |k| mapping[k].present? }

        %i[positive negative].filter_map { |sign| build_split_variant(mapping, sign) }
      end

      def build_split_variant(mapping, sign)
        measurement = mapping[:"measurement_#{sign}"]
        field = mapping[:"field_#{sign}"]
        return nil if measurement.blank? || field.blank?

        variant = mapping.except(*SPLIT_FIELDS).merge(measurement:, field:)
        apply_sign_filter!(variant, sign)
        variant
      end

      # Rewrite value extraction so the collector only emits the matching half.
      # The non-matching sign falls back to 0 (not NULL) so the time series stays gap-free —
      # InfluxDB aggregations (MEAN, SUM, integrals) behave predictably only with continuous data.
      def apply_sign_filter!(variant, sign)
        target_key, reference = sign_filter_target(variant)
        variant[target_key] = sign_formula(reference, sign)
      end

      def sign_filter_target(variant)
        return :json_formula, "{#{variant.delete(:json_key)}}" if variant[:json_key].present?
        return :json_formula, "{#{variant.delete(:json_path)}}" if variant[:json_path].present?
        return :json_formula, "(#{variant[:json_formula]})" if variant[:json_formula].present?
        return :formula, "(#{variant[:formula]})" if variant[:formula].present?

        [:formula, '{value}']
      end

      def sign_formula(ref, sign)
        sign == :positive ? "IF(#{ref} > 0, #{ref}, 0)" : "IF(#{ref} < 0, -#{ref}, 0)"
      end

      def mapping_indices(mqtt_env)
        mqtt_env.keys
                .filter_map { |k| k[/\AMAPPING_(\d+)_/, 1]&.to_i }
                .uniq
                .sort
      end

      def build_devices(device_mappings)
        # Group mappings by measurement name (one measurement = one device)
        grouped = device_mappings.group_by { |m| m[:measurement].presence }
        grouped.delete(nil) # skip mappings without measurement

        grouped.filter_map do |measurement, group|
          device_type = infer_device_type(measurement, group)
          next unless device_type

          field = DATA_SOURCE_FIELDS.fetch(device_type, 'data_source')
          data = { field => 'mqtt' }
          assign_topics(data, measurement, group)

          { type: device_type, name: measurement, data: }
        end
      end

      def assign_topics(data, measurement, device_mappings)
        device_mappings.each do |mapping|
          topic = mapping[:topic]
          next if topic.blank?

          candidate = "#{measurement}:#{mapping[:field]}"
          sensor_name = find_sensor_for_candidate(@sensors_data, candidate)
          topic_field = sensor_name ? SENSOR_TOPIC_FIELDS[sensor_name] : nil

          # Use specific topic field if known, otherwise set generic mqtt_topic
          data[topic_field || 'mqtt_topic'] ||= topic
        end
      end

      def infer_device_type(measurement, device_mappings)
        device_mappings.each do |mapping|
          candidate = "#{measurement}:#{mapping[:field]}"
          type = find_device_type_for_candidate(candidate)
          return type if type
        end

        'consumer'
      end

      def find_device_type_for_candidate(candidate)
        @sensors_data.each do |sensor_name, sensor_value|
          next unless sensor_value == candidate

          return 'inverter' if sensor_name.match?(/\Ainverter_power(_\d)?\z/)
          return 'consumer' if sensor_name.match?(/\Acustom_power_\d{2}\z/)
          return SENSOR_DEVICE_TYPE[sensor_name] if SENSOR_DEVICE_TYPE.key?(sensor_name)
        end

        nil
      end
    end
  end
end
