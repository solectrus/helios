module Import
  class ConfigurationImporter
    class MqttExtractor
      include Helpers

      MAPPING_FIELDS = %i[
        topic measurement field json_key json_path json_formula
        measurement_positive measurement_negative field_positive field_negative
        type min max null_to_zero
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
        mapping_indices(mqtt_env).map do |i|
          MAPPING_FIELDS.index_with { |f| mqtt_env["MAPPING_#{i}_#{f.upcase}"] }.compact
        end
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
