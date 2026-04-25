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

    def unit
      SensorRegistry.unit_for(sensor_name)
    end

    def description
      I18n.t("sensors.#{sensor_name}")
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

    def boolean_value?
      raw_value.is_a?(String) && raw_value.match?(/\A(?:true|false)\z/i)
    end

    def boolean_label
      raw_value&.casecmp('true')&.zero? ? I18n.t('common.boolean_yes') : I18n.t('common.boolean_no')
    end

    def value?
      raw_value.present?
    end

    def formatted_value
      @formatted_value ||=
        if raw_value.nil?
          '—'
        elsif raw_value.is_a?(Numeric)
          raw_value == raw_value.to_i ? raw_value.to_i.to_s : format('%.1f', raw_value)
        else
          raw_value.to_s
        end
    end

    def freshness_class
      return 'text-base-content/30' if raw_value.nil?
      return 'text-warning' if reading&.dig(:time)&.< 1.hour.ago

      'text-success'
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

    def timestamp
      reading&.dig(:time)
    end

    def timestamp_iso
      timestamp&.iso8601
    end

    private

    def raw_value
      reading&.dig(:value)
    end
  end
end
