module MqttTopicsTable
  class Component < ViewComponent::Base
    attr_reader :topics, :readings

    delegate :empty?, to: :topics

    def initialize(topics:, readings: {})
      super()
      @topics = topics
      @readings = readings
    end

    def reading_for(index)
      readings[index.to_s]
    end

    def polling_enabled?
      readings.present?
    end

    def extraction_for(topic)
      key = Surveys::MqttFields::EXTRACTION_KEYS.find { |k| topic[k].present? }
      return { label: t('datasources.mqtt_topics.extraction.plain'), value: nil } unless key

      { label: t("datasources.mqtt_topics.extraction.#{key}"), value: topic[key] }
    end

    def filters_for(topic)
      chips = []
      chips << "min #{topic['min']}" if topic['min'].present?
      chips << "max #{topic['max']}" if topic['max'].present?
      chips << t('datasources.mqtt_topics.filters.null_to_zero') if topic['null_to_zero']
      chips
    end
  end
end
