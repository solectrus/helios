module MqttTopicsTable
  class Component < ViewComponent::Base
    attr_reader :topics, :readings, :graph

    delegate :empty?, to: :topics

    def initialize(topics:, graph:, readings: {})
      super()
      @topics = topics
      @graph = graph
      @readings = readings
    end

    # Entries whose formula reads this one by name. Removing it would leave a
    # reference that no mapping defines, so the button is disabled and names
    # who stands in the way.
    def blockers_for(topic)
      graph.dependents_of(topic['name'])
    end

    def delete_tooltip_class(blockers)
      blockers.any? ? 'tooltip-warning before:text-left before:text-xs' : 'tooltip-info'
    end

    def delete_tip(blockers)
      return t('datasources.mqtt_topics.table.delete') if blockers.empty?

      t('datasources.mqtt_topics.index.delete_blocked', names: blockers.join(', '))
    end

    def reading_for(index)
      readings[index.to_s]
    end

    def polling_enabled?
      readings.present?
    end

    # A mapping without a topic calculates its value from other mappings, so
    # its formula takes the place the topic holds for the others.
    def computed?(topic)
      topic['topic'].blank?
    end

    def headline_for(topic)
      computed?(topic) ? topic['formula'] : topic['topic']
    end

    # SKIP_WRITE keeps the value in memory for formulas to read, so there is no
    # InfluxDB target to show.
    def stored?(topic)
      !truthy?(topic['skip_write'])
    end

    # The badges below the headline, in display order. An option that is not
    # set is left out.
    def badges_for(topic)
      [
        extraction_badge(topic),
        name_badge(topic),
        max_age_badge(topic),
        range_badge(topic),
        null_to_zero_badge(topic),
        aggregate_badge(topic),
        dedup_badge(topic),
      ].compact.each_with_index.map { |attributes, index| badge_component(attributes, leading: index.zero?) }
    end

    def type_badge(topic)
      return if topic['type'].blank?

      badge_component(badge(topic['type'], tip: t('datasources.mqtt_topics.target.type_tip')))
    end

    # Stands where a target would stand, so an outline says that nothing is
    # written there.
    def skip_write_badge
      badge_component(
        badge(t('datasources.mqtt_topics.target.skip_write'),
              tip: t('datasources.mqtt_topics.target.skip_write_tip'),
              icon: 'fa-memory',
              style: 'badge-dash'),
        leading: true,
      )
    end

    private

    # The list clips what leaves it. A badge at the start of a row therefore
    # opens its tooltip to the right, where the whole width is free.
    def badge_component(attributes, leading: false)
      Badge::Component.new(**attributes, tip_position: leading ? 'tooltip-right' : 'tooltip-top')
    end

    # An option shows up as a short badge. What it means is in the tooltip, so
    # the row stays readable at a glance.
    def badge(text = nil, tip: nil, icon: nil, style: Badge::Component::DEFAULT_STYLE)
      { text:, tip:, icon:, style: }
    end

    # How the value is taken out of the payload. A calculated entry already
    # shows its formula as the headline, so it needs no badge.
    def extraction_badge(topic)
      return if computed?(topic)

      key = Surveys::MqttFields::EXTRACTION_KEYS.find { |k| topic[k].present? }
      return if key.nil?

      badge(topic[key], tip: t("datasources.mqtt_topics.extraction.#{key}"), icon: 'fa-code')
    end

    # The name a formula reads this mapping by.
    def name_badge(topic)
      return if topic['name'].blank?

      badge(topic['name'], tip: t('datasources.mqtt_topics.naming.tip'), icon: 'fa-tag')
    end

    # How long the value stays usable for formulas.
    def max_age_badge(topic)
      return if topic['max_age'].blank?

      badge(t('datasources.mqtt_topics.naming.max_age', seconds: topic['max_age']),
            tip: t('datasources.mqtt_topics.naming.max_age_tip', seconds: topic['max_age']),
            icon: 'fa-hourglass-half')
    end

    def range_badge(topic)
      min = topic['min']
      max = topic['max']
      text =
        if min.present? && max.present?
          t('datasources.mqtt_topics.filters.range', min:, max:)
        elsif min.present?
          t('datasources.mqtt_topics.filters.min', min:)
        elsif max.present?
          t('datasources.mqtt_topics.filters.max', max:)
        end
      return if text.nil?

      badge(text, tip: t('datasources.mqtt_topics.filters.range_tip'), icon: 'fa-filter')
    end

    def null_to_zero_badge(topic)
      return unless truthy?(topic['null_to_zero'])

      badge(t('datasources.mqtt_topics.filters.null_to_zero'),
            tip: t('datasources.mqtt_topics.filters.null_to_zero_tip'))
    end

    def aggregate_badge(topic)
      return if topic['aggregate_interval'].blank?

      badge(t('datasources.mqtt_topics.write_behavior.aggregate', seconds: topic['aggregate_interval']),
            tip: t('datasources.mqtt_topics.write_behavior.aggregate_tip', seconds: topic['aggregate_interval']))
    end

    # Deduplication only writes what changed. The icon says that on its own, so
    # the words stay in the tooltip, together with the heartbeat that sets how
    # often the value reaches InfluxDB anyway.
    def dedup_badge(topic)
      return unless truthy?(topic['dedup'])

      seconds = topic['heartbeat_interval'].presence || ConfigSchema::MQTT_DEFAULT_HEARTBEAT_INTERVAL

      badge(tip: t('datasources.mqtt_topics.write_behavior.dedup_tip', seconds:), icon: 'fa-code-compare')
    end

    # A mapping saved through the survey holds a real boolean, one imported
    # before HELIOS cast them still holds the env string. In Ruby the string
    # "false" is true, so a plain check would show an option that is off.
    def truthy?(value)
      value == true || value.to_s == 'true'
    end
  end
end
