module MqttTopicForm
  class Component < ViewComponent::Base
    attr_reader :index, :data

    def initialize(index: nil, data: nil)
      super()
      @index = index
      @data = data
    end

    def new_record?
      index.nil?
    end

    def form_url
      if new_record?
        helpers.datasources_mqtt_topics_path
      else
        helpers.datasources_mqtt_topic_path(index)
      end
    end

    def form_method
      new_record? ? :post : :patch
    end

    # The survey needs to know which entry is being edited: a name must be
    # unique among the others, and a formula must not reference an entry that
    # reads this one.
    def survey_url
      helpers.configuration_survey_path('mqtt_topic', format: :json, index:)
    end

    # The UI-only answers travel with the stored fields; MQTT_TOPIC_FIELDS
    # drops them again on save.
    def setting_data_json
      return '{}' if new_record? || data.blank?

      data.merge(Surveys::MqttFields.ui_state(data)).to_json
    end
  end
end
