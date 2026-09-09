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

      badge = tag.span(source_badge_label,
                       class: "badge badge-sm uppercase #{source_badge_css}")
      return badge unless ingest_hint?

      tag.span(safe_join([badge, ingest_hint_icon]), class: 'inline-flex items-center gap-1')
    end

    # While Ingest runs, an external source has to write to Ingest instead of
    # InfluxDB, otherwise its value never enters the house-power calculation
    # and Ingest writes no house power at all (see Configuration#ingest_required?).
    def ingest_hint?
      source == 'external' &&
        SensorRegistry::INGEST_SENSORS.include?(sensor_name) &&
        configuration.ingest_required?
    end

    # Its own content element rather than data-tip, so the sentence reads
    # left-aligned like the exclusion list above it.
    def ingest_hint_icon
      icon = tag.i(class: 'fa-solid fa-circle-info text-base-content/70 text-sm leading-none')

      tag.span(safe_join([ingest_hint_content, icon]), class: 'tooltip tooltip-left flex items-center')
    end

    def ingest_hint_content
      lead = safe_join([tag.strong(I18n.t('sensors.ingest_endpoint_hint_lead')), ' ', ingest_hint_tooltip])
      body = safe_join(
        [
          tag.span(lead, class: 'block'),
          tag.span(I18n.t('sensors.ingest_endpoint_hint_consequence'), class: 'mt-2 block'),
        ],
      )

      tag.span(
        tag.span(body, class: 'block max-w-3xs px-1 py-0.5 text-left text-xs font-normal normal-case'),
        class: 'tooltip-content',
      )
    end

    # Without a known address the hint names the port instead, so no
    # placeholder host ends up in front of the user.
    def ingest_hint_tooltip
      url = Export::IngestEndpoint.url(configuration)
      return I18n.t('sensors.ingest_endpoint_hint', url:) if url

      I18n.t('sensors.ingest_endpoint_hint_port', port: Export::IngestEndpoint::PORT)
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

    # The tooltip names consumers the way the list does, so a custom sensor
    # appears under the label its owner gave it.
    def excluded_power_sensor_labels
      excluded_power_sensors.map do |name|
        configuration.sensor_config(name).name.presence || I18n.t("sensors.#{name}")
      end
    end
  end
end
