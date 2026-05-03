module Export
  class Env
    class Sensors < Section
      def call
        mappings = configuration.effective_sensor_mappings
        return if mappings.blank?

        env.add_section('Sensor mappings')
        SensorRegistry::SENSORS.each_key do |sensor|
          value = mappings[sensor]
          next if value.blank?

          entry("INFLUX_SENSOR_#{sensor.upcase}", value, "Sensor: #{sensor}")
        end
      end
    end
  end
end
