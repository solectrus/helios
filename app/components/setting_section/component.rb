module SettingSection
  class Component < ViewComponent::Base
    ICONS = {
      'forecast' => 'fa-cloud-sun',
      'deployment' => 'fa-sitemap',
      'software' => 'fa-code-branch',
      'system_general' => 'fa-sliders',
      'system_security' => 'fa-key',
      'dashboard_co2' => 'fa-leaf',
      'dashboard_theme' => 'fa-palette',
      'reverse_proxy' => 'fa-network-wired',
      'backup' => 'fa-cloud-arrow-up',
      'senec' => 'fa-bolt',
      'tibber' => 'fa-euro-sign',
      'mqtt' => 'fa-tower-broadcast',
      'shelly' => 'fa-plug-circle-bolt',
      'influxdb' => 'fa-database',
      'ingest_settings' => 'fa-house-signal',
      'storage' => 'fa-hard-drive',
    }.freeze

    # Settings whose card says how the collector reaches its device: over the
    # local network or through the vendor cloud. That decides what the
    # collector can read, so the card names it instead of only "configured".
    ACCESS_FIELDS = { 'shelly' => :connection, 'senec' => :adapter }.freeze

    FORECAST_PROVIDERS = {
      'pvnode' => 'pvnode',
      'solcast' => 'Solcast',
      'forecast.solar' => 'Forecast.Solar',
    }.freeze

    attr_reader :setting, :configuration

    def initialize(setting:, configuration:)
      super()
      @setting = setting
      @configuration = configuration
    end

    def icon
      self.class.icon_for(setting)
    end

    def title
      I18n.t("configurations.settings.#{setting}.title")
    end

    def description
      I18n.t("configurations.settings.#{setting}.description", default: nil)
    end

    def link_path
      if toggled_on?
        helpers.edit_configuration_setting_path(setting:, name: setting)
      else
        helpers.new_configuration_setting_path(setting:)
      end
    end

    def singleton_data
      @singleton_data ||= configuration.setting_data(setting)
    end

    # First line of the status: what the value below it is. Every card that
    # has something to say names it the same way, so the row reads as one.
    def status_label
      return broker_label if setting == 'mqtt'
      return I18n.t('configurations.show.access') if access
      return I18n.t('configurations.show.provider') if forecast_provider_known?

      I18n.t('configurations.show.configured')
    end

    # Local or cloud, for the cards that reach a device. Nil where the section
    # names neither, and the card then falls back to the plain label.
    def access
      field = ACCESS_FIELDS[setting]
      return unless field

      value = singleton_data.public_send(field)
      value if %w[local cloud].include?(value)
    end

    def status_text
      return I18n.t('configurations.show.incomplete') if incomplete?
      return status_label if toggled_on?

      I18n.t('configurations.settings.not_configured')
    end

    # Source cards stand on the data sources screen whether or not they are in
    # use (see Configuration#offered_sources). A card that is only on offer is
    # dimmed, and its switch is the one thing on it that reacts: the rest
    # opens once the source is switched on.
    def dimmed?
      !toggled_on?
    end

    # The switch that puts a source on the installation, right on its card.
    # On means the source has settings of its own, which is the same rule that
    # lets it be switched off again (Configuration#source_droppable?).
    # Switching it on opens the survey, because a source that names no host
    # and no provider cannot read anything. Switching it off needs no question
    # and takes the settings away.
    def toggled_on?
      configuration.source_droppable?(setting)
    end

    def toggle_title
      I18n.t("configurations.settings.toggle_#{toggled_on? ? 'off' : 'on'}")
    end

    # Switching off deletes the settings of the source, and deactivates the
    # sensors that read through it: they would have nothing left to read. That
    # is the part worth a warning, so the question names how many.
    def toggle_confirm
      return I18n.t('configurations.settings.toggle_confirm') if sensor_count.zero?

      I18n.t('configurations.settings.toggle_confirm_sensors', count: sensor_count)
    end

    # Second line of the status, the value its first line names.
    def status_value
      return unless addressable?

      case setting
      when 'mqtt' then broker_address
      when 'shelly', 'senec' then I18n.t("configurations.show.access_#{access}") if access
      when 'forecast' then FORECAST_PROVIDERS[singleton_data.forecast]
      end
    end

    # Third line: behind the managed Traefik the broker answers on a second,
    # encrypted port as well. No survey names it any more, so the card is the
    # only place it can stand. It repeats the whole address rather than the
    # port alone, because only the name reaches that port: Traefik reads it
    # out of the TLS handshake (HostSNI, see Mosquitto#traefik_labels). A
    # padlock marks the line instead of the word TLS, which costs twice the
    # width.
    def status_tls
      return unless addressable? && setting == 'mqtt' && managed_broker?
      return unless Export::Services::Mosquitto.traefik_managed_routing?(configuration)

      "#{configuration.public_host}:#{Export::Services::Mosquitto::TLS_HOST_PORT}"
    end

    def addressable?
      toggled_on? && !incomplete?
    end

    def status_text_class
      return 'text-warning' if incomplete?
      return 'text-base-content/70' if toggled_on?

      'text-base-content/55'
    end

    def forecast_provider_known?
      setting == 'forecast' && FORECAST_PROVIDERS.key?(singleton_data.forecast)
    end

    # The broker is the part of the MQTT card a user looks for and would not
    # expect behind a collector, so the card names whose broker it is and
    # where it answers. That is also the screen both can be changed on.
    def managed_broker?
      configuration.mqtt_broker_managed?
    end

    def broker_label
      I18n.t("configurations.show.#{managed_broker? ? 'broker_managed' : 'broker_external'}")
    end

    # `host:port`, the way a device is pointed at a broker. HELIOS knows the
    # port of its own broker, but the address of its host only where the
    # configuration names one, so the port stands alone until it does.
    def broker_address
      if managed_broker?
        address(configuration.public_host, Export::Services::Mosquitto.host_port(configuration))
      else
        address(configuration.mqtt.mqtt_host, configuration.mqtt.mqtt_port)
      end
    end

    def address(host, port)
      return I18n.t('configurations.show.broker_port', port:) if host.blank?

      [host, port].compact_blank.join(':')
    end

    def incomplete?
      configuration.setting_incomplete?(setting)
    end

    def self.icon_for(setting)
      ICONS[setting] || 'fa-circle-question'
    end

    # Every source card ends on the same figure: how many sensors read through
    # it. That is what a source is there for, so it is the one number the
    # cards can be compared by. Skipped in collectors_only mode, which imports
    # no logical sensors and sends the sensors screen back here.
    def sensor_count?
      !configuration.collectors_only?
    end

    def sensor_count
      configuration.sensors_with_source(setting).size
    end

    # Topics and devices that stand on their own, beside the sensors. They
    # belong to the source itself, so the body of the card names them and the
    # footer keeps the one figure every card carries.
    #
    # The Shelly device CRUD is reachable in collectors_only mode and, in full
    # mode, for multi-device setups where `shelly.devices` is a standalone
    # array — single-device full-mode setups derive the device from the
    # `source: shelly` sensor and are edited on the Sensors screen instead.
    def extras
      case setting
      when 'mqtt' then mqtt_extras
      when 'shelly' then shelly_extras
      end
    end

    private

    def mqtt_extras
      # In full mode, sensors set on MQTT define their own topics. The ones
      # listed here are extras the user adds explicitly — surface that.
      label_key = configuration.collectors_only? ? 'label' : 'additional_label'
      {
        path: helpers.datasources_mqtt_topics_path,
        label: I18n.t("datasources.mqtt_topics.inline.#{label_key}"),
        count: configuration.mqtt_topics.size,
      }
    end

    def shelly_extras
      devices = configuration.shelly_devices
      return unless configuration.collectors_only? || devices.any?

      {
        path: helpers.datasources_shelly_devices_path,
        label: I18n.t('datasources.shelly_devices.inline.label'),
        count: devices.size,
      }
    end
  end
end
