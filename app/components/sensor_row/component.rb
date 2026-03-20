module SensorRow
  class Component < ViewComponent::Base
    SOURCE_BADGES = {
      'senec' => { label: 'SENEC', css: 'badge-primary' },
      'shelly' => { label: 'Shelly', css: 'badge-secondary' },
      'mqtt' => { label: 'MQTT', css: 'badge-accent' },
      'forecast' => { label: 'Forecast', css: 'badge-info' },
      'smart_home' => { label: 'Smart Home', css: 'badge-warning' },
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

    def source_badge
      SOURCE_BADGES[source]
    end

    def unit
      SensorRegistry.unit_for(sensor_name)
    end

    def description
      I18n.t("sensors.#{sensor_name}")
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

    def formatted_value
      value = reading&.dig(:value)
      return '—' if value.nil?

      if value.is_a?(Numeric)
        value == value.to_i ? value.to_i.to_s : format('%.1f', value)
      else
        value.to_s
      end
    end

    def freshness_class
      value = reading&.dig(:value)
      time = reading&.dig(:time)
      return 'text-base-content/30' if value.nil?
      return 'text-warning' if time && time < 1.hour.ago

      'text-success'
    end
  end
end
