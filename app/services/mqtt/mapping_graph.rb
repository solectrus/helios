module Mqtt
  # Who may reference whom in an mqtt-collector formula.
  #
  # From version 0.8.0 a mapping can carry a MAPPING_X_NAME, and a mapping
  # without a topic calculates its value from other mappings by that name
  # (`{washer} - {dryer}`). HELIOS writes such mappings from two places: a
  # sensor with source `mqtt`, and a standalone entry under `mqtt.mappings`.
  # This class is the single place that knows about both.
  #
  # It exists because the collector refuses to start on an unknown reference or
  # a formula cycle, and that refusal is only visible in the collector's own
  # log. The surveys therefore offer just the references that are safe, instead
  # of letting a mistake reach the exported file.
  class MappingGraph
    # What the collector accepts as a MAPPING_X_NAME (its MAPPING_NAME_REGEX).
    # The survey validates against the same rule, so a name the form allows is
    # always a name the scan below can find again.
    NAME_FORMAT = /[a-z_][a-z0-9_]*/

    # Matches a formula reference. A name is restricted to exactly these
    # characters, so a plain scan is enough and no formula parser is needed.
    REFERENCE = /\{(#{NAME_FORMAT})\}/

    # An entry of either kind, reduced to what the graph cares about.
    Node = Struct.new(:key, :name, :formula, :label, keyword_init: true)

    def initialize(configuration)
      @configuration = configuration
    end

    def names
      @names ||= nodes.filter_map(&:name)
    end

    # The name this entry carries, so a caller does not have to read it out of
    # the configuration a second time.
    def name_of(key)
      node_for(key)&.name
    end

    # Names another entry already uses, so a survey can refuse a duplicate.
    def names_used_by_others(key)
      nodes.reject { |node| node.key == key }.filter_map(&:name)
    end

    # Names this entry's formula may reference: every name except its own and
    # except those that read it, directly or through a chain. Leaving the
    # cycle-forming names out means HELIOS needs no cycle error of its own.
    def referencable_from(key)
      own = node_for(key)
      return names unless own&.name

      names - dependent_names(own.name) - [own.name]
    end

    # Labels of the entries whose formula reads this name, for a message that
    # says who would break.
    def dependents_of(name)
      return [] if name.blank?

      readers_of(name).map(&:label)
    end

    private

    attr_reader :configuration

    def nodes
      @nodes ||= sensor_nodes + topic_nodes
    end

    def sensor_nodes
      configuration.sensors_with_source('mqtt').map do |sensor_name, config|
        Node.new(
          key: [:sensor, sensor_name],
          name: config['mqtt_name'].presence,
          formula: config['mqtt_formula'],
          label: sensor_name,
        )
      end
    end

    def topic_nodes
      configuration.mqtt_topics.each_with_index.map do |topic, index|
        Node.new(
          key: [:topic, index],
          name: topic['name'].presence,
          formula: topic['formula'],
          label: topic_label(topic, index),
        )
      end
    end

    # How a standalone entry is named in a message. A calculated one has no
    # topic, so its destination identifies it; a memory-only one has neither
    # and falls back to its position in the list.
    def topic_label(topic, index)
      target = [topic['measurement'], topic['field']].compact_blank.join(':')

      topic['name'].presence || topic['topic'].presence || target.presence || "##{index + 1}"
    end

    def node_for(key)
      nodes.find { |node| node.key == key }
    end

    # Every formula scanned once, as name => the entries reading it. Built
    # eagerly because the walk below asks for one name after the other, and
    # each answer would otherwise rescan every formula in the configuration.
    def readers_by_name
      @readers_by_name ||=
        nodes.each_with_object({}) do |node, index|
          node.formula.to_s.scan(REFERENCE).flatten.uniq.each { |reference| (index[reference] ||= []) << node }
        end
    end

    def readers_of(name)
      readers_by_name.fetch(name, [])
    end

    # Every name that reaches `name` through a chain of formulas. Walks the
    # graph backwards from the readers, so a chain of any depth is covered.
    # Only a named reader can be walked on, an unnamed one is a dead end.
    def dependent_names(name)
      found = []
      pending = [name]

      while (current = pending.shift)
        fresh = readers_of(current).filter_map(&:name) - found
        found.concat(fresh)
        pending.concat(fresh)
      end

      found
    end
  end
end
