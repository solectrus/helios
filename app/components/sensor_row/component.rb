module SensorRow
  class Component < ViewComponent::Base
    SOURCE_BADGES = {
      'senec' => 'badge-outline text-cyan-300',
      'shelly' => 'badge-outline text-pink-300',
      'mqtt' => 'badge-outline text-amber-300',
      'forecast' => 'badge-outline text-sky-300',
      'external' => 'badge-outline text-slate-300',
    }.freeze

    attr_reader :sensor_name, :configuration, :reading

    def initialize(sensor_name:, configuration:, reading: nil)
      super()
      @sensor_name = sensor_name
      @configuration = configuration
      @reading = reading
    end

    def enabled?
      configuration.sensor_enabled?(sensor_name)
    end

    def sensor_config
      @sensor_config ||= configuration.sensor_config(sensor_name)
    end

    delegate :source, to: :sensor_config

    def source_badge_css
      SOURCE_BADGES[source]
    end

    def source_badge_label
      t(".sources.#{source}")
    end

    # Rendered in two places: a dedicated column on desktop and inline next to
    # the sensor name on mobile. Returns nil for disabled or sourceless sensors.
    def source_badge
      return unless enabled? && source_badge_css

      tag.span(source_badge_label,
               class: "badge badge-sm uppercase #{source_badge_css}")
    end

    def unit
      SensorRegistry.unit_for(sensor_name)
    end

    # Hint shown in the value cell when no live value exists yet: the physical
    # unit (W, %, °C) or a yes/no marker for boolean sensors. Status sensors
    # have neither.
    def unit_label
      return unit if unit.present?

      if SensorRegistry.boolean?(sensor_name)
        return "#{I18n.t('common.boolean_yes')}/#{I18n.t('common.boolean_no')}"
      end

      nil
    end

    def description
      I18n.t("sensors.#{sensor_name}")
    end

    # Prominent, human-readable label. Custom sensors prefer the user-supplied
    # name and fall back to the generic "Consumer N" description.
    def display_label
      return custom_name if custom_sensor? && custom_name

      description
    end

    def custom_sensor?
      sensor_name.start_with?('custom_power_')
    end

    def custom_name
      sensor_config.name.presence
    end

    def edit_path
      helpers.edit_configuration_setting_path(setting: 'sensor', name: sensor_name)
    end

    def new_path
      helpers.new_configuration_setting_path(setting: 'sensor', name: sensor_name)
    end

    def destroy_path
      helpers.configuration_setting_path(setting: 'sensor', name: sensor_name)
    end

    delegate :value?, :timestamp_iso, :freshness_class, :boolean_label, to: :reading, allow_nil: true

    def boolean_value?
      reading&.boolean? || false
    end

    def formatted_value
      reading&.formatted(precision: 1) || Reading::EMPTY_DISPLAY
    end

    # Sensors excluded from house power in SOLECTRUS
    def house_power_exclusions?
      sensor_name == 'house_power' && excluded_power_sensors.any?
    end

    def excluded_power_sensors
      @excluded_power_sensors ||= configuration.enabled_sensors.select do |name|
        configuration.sensor_config(name).exclude_from_house_power == true
      end
    end

    def house_power_exclusion_tooltip
      names = excluded_power_sensors.map(&:upcase).join(', ')
      I18n.t('sensors.house_power_exclusion_hint', sensors: names)
    end
  end
end
