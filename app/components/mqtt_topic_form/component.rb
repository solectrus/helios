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

    def survey_url
      helpers.configuration_survey_path('mqtt_topic', format: :json)
    end

    def setting_data_json
      return '{}' if new_record? || data.blank?

      data.merge('extraction_method' => extraction_method).to_json
    end

    private

    def extraction_method
      Surveys::MqttFields::EXTRACTION_KEYS.find { |k| data[k].present? } || 'plain'
    end
  end
end
