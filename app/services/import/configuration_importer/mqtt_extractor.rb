module Import
  class ConfigurationImporter
    class MqttExtractor # rubocop:disable Metrics/ClassLength
      include Helpers

      SPLIT_FIELDS = %i[
        measurement_positive measurement_negative field_positive field_negative
      ].freeze

      # Every field of a mapping, read back under the same name it is written
      # under, plus the sign-split vars the collector accepts on top. Derived
      # from the schema, so an option the export emits cannot be dropped here.
      MAPPING_FIELDS = (ConfigSchema::MQTT_MAPPING_FIELDS.map(&:to_sym) + SPLIT_FIELDS).freeze

      # Mapping options mqtt-collector reads as a flag. It accepts exactly
      # "true" or "false" for them (Config#validate_mapping! with an allow
      # list), while the surveys store a real boolean. Keeping the env string
      # would leave two shapes for one field in config.yaml, and in Ruby the
      # string "false" is true.
      BOOLEAN_FIELDS = %i[null_to_zero dedup skip_write].freeze

      # Pre-MAPPING-style env vars that mqtt-collector still accepts for backward
      # compatibility (see mqtt-collector/lib/config.rb DEPRECATED_ENV). Each maps
      # to a fixed (field, type) pair; the measurement comes from INFLUX_MEASUREMENT.
      DEPRECATED_TOPIC_VARS = {
        'MQTT_TOPIC_HOUSE_POW' => %w[house_power integer],
        'MQTT_TOPIC_BAT_FUEL_CHARGE' => %w[bat_fuel_charge float],
        'MQTT_TOPIC_CASE_TEMP' => %w[case_temp float],
        'MQTT_TOPIC_CURRENT_STATE' => %w[current_state string],
        'MQTT_TOPIC_MPP1_POWER' => %w[mpp1_power integer],
        'MQTT_TOPIC_MPP2_POWER' => %w[mpp2_power integer],
        'MQTT_TOPIC_MPP3_POWER' => %w[mpp3_power integer],
        'MQTT_TOPIC_INVERTER_POWER' => %w[inverter_power integer],
        'MQTT_TOPIC_POWER_RATIO' => %w[power_ratio integer],
        'MQTT_TOPIC_WALLBOX_CHARGE_POWER' => %w[wallbox_charge_power integer],
        'MQTT_TOPIC_WALLBOX_CHARGE_POWER1' => %w[wallbox_charge_power1 integer],
        'MQTT_TOPIC_WALLBOX_CHARGE_POWER2' => %w[wallbox_charge_power2 integer],
        'MQTT_TOPIC_WALLBOX_CHARGE_POWER3' => %w[wallbox_charge_power3 integer],
        'MQTT_TOPIC_HEATPUMP_POWER' => %w[heatpump_power integer],
      }.freeze

      # Sign-split vars have a corresponding MQTT_FLIP_* that swaps the
      # positive/negative field assignment. Mirrors mqtt-collector's behaviour.
      DEPRECATED_SPLIT_VARS = {
        'MQTT_TOPIC_GRID_POW' => {
          field: 'grid_power',
          type: 'integer',
          flip_var: 'MQTT_FLIP_GRID_POW',
        },
        'MQTT_TOPIC_BAT_POWER' => {
          field: 'bat_power',
          type: 'integer',
          flip_var: 'MQTT_FLIP_BAT_POWER',
        },
      }.freeze

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

      # Raw MAPPING_N_* entries as plain hashes, ready to persist to
      # mqtt.mappings in collectors_only mode where HELIOS cannot (and does
      # not try to) map them back to canonical sensor names.
      def raw_mappings
        @raw_mappings ||= build_raw_mappings
      end

      # Orphan = no HELIOS sensor reads it. Preserved so the user's
      # mqtt-collector keeps writing the topic to InfluxDB after re-export,
      # avoiding a gap in the time series.
      def orphan_mappings
        return [] unless enabled?

        raw_mappings.reject { |raw| raw_mapping_consumed?(raw) }
      end

      private

      def build_raw_mappings
        return [] unless enabled?

        mqtt_env = service_env('mqtt-collector')
        mapping_indices(mqtt_env).map do |i|
          MAPPING_FIELDS.each_with_object({}) do |f, hash|
            value = mqtt_env["MAPPING_#{i}_#{f.upcase}"]
            hash[f.to_s] = cast(f, value) if value.present?
          end
        end.reject(&:empty?)
      end

      # Anything the collector would refuse anyway stays as it arrived, so a
      # wrong value remains visible instead of turning into a silent false.
      def cast(field, value)
        return value unless BOOLEAN_FIELDS.include?(field)

        case value
        when 'true' then true
        when 'false' then false
        else value
        end
      end

      # Sign-split mappings (FIELD_POSITIVE/_NEGATIVE) round-trip through the
      # matched sensor on either side, so a single side-match counts as
      # consumed for the whole raw entry.
      def raw_mapping_consumed?(raw)
        symbolized = raw.transform_keys(&:to_sym)
        expand_sign_split(symbolized).any? do |expanded|
          measurement = expanded[:measurement]
          field = expanded[:field]
          next false if measurement.blank? || field.blank?

          find_sensor_for_candidate(@sensors_data, "#{measurement}:#{field}")
        end
      end

      def parse_mappings(mqtt_env)
        raw = mapping_indices(mqtt_env).map do |i|
          MAPPING_FIELDS.index_with { |f| mqtt_env["MAPPING_#{i}_#{f.upcase}"] }
                        .compact
                        .to_h { |f, value| [f, cast(f, value)] }
        end
        raw.concat(parse_deprecated_mappings(mqtt_env))
        raw.flat_map { |m| expand_sign_split(m) }
      end

      # Legacy mqtt-collector installs only expose MQTT_TOPIC_* (plus MQTT_FLIP_*
      # for sign-split vars). Synthesize the equivalent modern mappings so the
      # rest of the import pipeline treats them like first-class configurations.
      def parse_deprecated_mappings(mqtt_env)
        measurement = mqtt_env['INFLUX_MEASUREMENT']
        return [] if measurement.blank?

        plain = DEPRECATED_TOPIC_VARS.filter_map do |var, (field, type)|
          next if mqtt_env[var].blank?

          { topic: mqtt_env[var], measurement: measurement, field: field, type: type }
        end

        split = DEPRECATED_SPLIT_VARS.filter_map do |var, info|
          next if mqtt_env[var].blank?

          build_deprecated_split(mqtt_env[var], info, measurement, mqtt_env[info[:flip_var]])
        end

        plain + split
      end

      def build_deprecated_split(topic, info, measurement, flip_value)
        flipped = flip_value.to_s == 'true'
        positive_field = flipped ? "#{info[:field]}_minus" : "#{info[:field]}_plus"
        negative_field = flipped ? "#{info[:field]}_plus" : "#{info[:field]}_minus"

        {
          topic: topic,
          measurement_positive: measurement,
          measurement_negative: measurement,
          field_positive: positive_field,
          field_negative: negative_field,
          type: info[:type],
        }
      end

      # mqtt-collector's sign-based splitting (MEASUREMENT_POSITIVE/NEGATIVE + FIELD_POSITIVE/NEGATIVE)
      # writes one topic into two Influx locations. HELIOS models one sensor = one Influx target,
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

      # A device is inferred from the topics that feed a measurement. A
      # calculated mapping has no topic and stands for no device, so it must not
      # conjure one out of its measurement alone.
      def build_devices(device_mappings)
        # Group mappings by measurement name (one measurement = one device)
        grouped = device_mappings.select { |m| m[:topic].present? }.group_by { |m| m[:measurement].presence }
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
