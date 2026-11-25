module RestartReason
  # Lists in plain words what a pending restart of a service will apply: the
  # sensors that came, went or changed, a new version, changed storage or
  # network settings, other settings and changed Docker settings.
  class Component < ViewComponent::Base
    SENSOR_PREFIX = 'INFLUX_SENSOR_'.freeze
    MAX_ITEMS = 4

    # Parts of the service definition a user changes through a setting, in
    # the order the list names them.
    PART_CATEGORIES = {
      'image' => :version,
      'volumes' => :storage,
      'ports' => :network,
      'networks' => :network,
      'labels' => :network,
    }.freeze

    # Every other part only moves when HELIOS changes the export. These have
    # a name of their own, the rest counts as "other".
    DOCKER_PARTS = {
      'healthcheck' => :healthcheck,
      'logging' => :logging,
      'command' => :command,
      'entrypoint' => :command,
      'restart' => :restart,
      'depends_on' => :depends_on,
    }.freeze

    # new_version: a newer image waits besides the changed configuration.
    def initialize(change:, new_version: false)
      super()
      @change = change
      @new_version = new_version
    end

    def render?
      entries.any?
    end

    private

    attr_reader :change, :new_version

    def items
      list = entries.map { |key, argument| label(key, argument) }
      list << t('.new_version') if new_version
      shortened(list)
    end

    def label(key, argument)
      return t(".#{key}", name: argument) unless key == :docker

      t('.docker', names: argument.map { |part| t(".parts.#{part}") }.join(', '))
    end

    def shortened(list)
      return list if list.size <= MAX_ITEMS

      shown = list.first(MAX_ITEMS - 1)
      shown + [t('.more', count: list.size - shown.size)]
    end

    # [i18n key, argument] pairs, translated only while rendering.
    def entries
      return [] if change.blank?

      @entries ||= sensor_entries + category_entries + docker_entries
    end

    def sensor_entries
      { sensor_added: change.added, sensor_changed: change.changed, sensor_removed: change.removed }
        .flat_map { |key, variables| variables.filter_map { |variable| sensor_label(variable) }.map { [key, it] } }
    end

    def category_entries
      found = change.parts.filter_map { |part| PART_CATEGORIES[part] }
      found << :other if variables.any? { |variable| sensor_label(variable).nil? }
      (PART_CATEGORIES.values.uniq + [:other]).intersection(found).map { [it, nil] }
    end

    def docker_entries
      parts = change.parts.reject { |part| PART_CATEGORIES.key?(part) }
      return [] if parts.empty?

      named = parts.map { |part| DOCKER_PARTS.fetch(part, :other) }.uniq
      [[:docker, named.partition { it != :other }.flatten]]
    end

    def variables
      change.added + change.changed + change.removed
    end

    def sensor_label(variable)
      return unless variable.start_with?(SENSOR_PREFIX)

      name = variable.delete_prefix(SENSOR_PREFIX).downcase
      return unless SensorRegistry.valid?(name)

      Configuration.current.sensor_config(name).name.presence || I18n.t("sensors.#{name}")
    end
  end
end
