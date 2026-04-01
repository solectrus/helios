module Import
  class ConfigurationImporter
    module Helpers
      # Maps device type to the field name that holds the data source identifier
      DATA_SOURCE_FIELDS = {
        'inverter' => 'battery_vendor',
        'wallbox' => 'wallbox_vendor',
        'heatpump' => 'heatpump_access',
      }.freeze

      private

      # Environment of a specific service (memoized per service name)
      def service_env(name)
        @service_envs ||= {}
        @service_envs[name] ||= @reader.service(name)&.dig('environment') || {}
      end

      def csv_split(value)
        value.to_s.split(',').map(&:strip)
      end

      def image_data_for(service_name)
        image = Compose.normalize_image(@reader.service(service_name)&.dig('image'))
        { 'image' => image }.compact
      end

      def find_sensor_for_candidate(sensors, candidate)
        sensors.find { |_, value| value == candidate }&.first
      end
    end
  end
end
