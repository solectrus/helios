module SensorTable
  class Component < ViewComponent::Base
    attr_reader :configuration, :readings

    delegate :preferences, to: :helpers

    def initialize(configuration:, readings: {})
      super()
      @configuration = configuration
      @readings = readings
    end

    def polling_enabled?
      readings.present?
    end

    def visible_groups
      SensorRegistry::GROUPS.filter_map do |group, sensor_names|
        visible = show_all? ? sensor_names : sensor_names.select { |s| configuration.sensor_enabled?(s) }
        [group, visible] if visible.any?
      end
    end

    def group_icon(group)
      SENSOR_GROUP_ICONS[group.to_sym] || 'fa-circle-question'
    end

    def show_all?
      preferences.show_all_sensors?
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
