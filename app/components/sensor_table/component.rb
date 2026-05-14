module SensorTable
  class Component < ViewComponent::Base
    attr_reader :configuration, :readings

    delegate :preferences, to: :helpers
    delegate :hide_unused?, to: :preferences

    def initialize(configuration:, readings: {})
      super()
      @configuration = configuration
      @readings = readings
    end

    def polling_enabled?
      readings.present?
    end

    def all_groups
      SensorRegistry::GROUPS.filter_map do |group, sensor_names|
        [group, sensor_names] if sensor_names.any?
      end
    end

    def group_icon(group)
      SENSOR_GROUP_ICONS[group.to_sym] || 'fa-circle-question'
    end

    SENSOR_GROUP_ICONS = {
      inverter: 'fa-solar-panel',
      grid: 'fa-plug',
      battery: 'fa-car-battery',
      wallbox: 'fa-charging-station',
      car: 'fa-car',
      heatpump: 'fa-fan',
      forecast: 'fa-cloud-sun',
      custom: 'fa-gauge',
    }.freeze
    private_constant :SENSOR_GROUP_ICONS
  end
end
