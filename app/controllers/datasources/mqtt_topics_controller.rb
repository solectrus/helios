module Datasources
  class MqttTopicsController < ApplicationController
    include TurboFrameOnly
    include SensorReadings

    before_action :set_configuration
    before_action :require_turbo_frame, only: %i[new edit]
    before_action :load_topic, only: %i[edit update destroy]

    def index
      @topics = @configuration.mqtt_topics
      @readings = fetch_topic_readings(configuration: @configuration)
    end

    def new
      render MqttTopicForm::Component.new
    end

    def edit
      render MqttTopicForm::Component.new(index: params[:id], data: @topic)
    end

    def create
      data = topic_params
      return unless data

      @configuration.add_mqtt_topic(data)
      Orchestration::StackStatus.mark_config_changed!
      redirect_to datasources_mqtt_topics_path
    end

    def update
      data = topic_params
      return unless data

      @configuration.update_mqtt_topic(params[:id], data)
      Orchestration::StackStatus.mark_config_changed!
      redirect_to datasources_mqtt_topics_path
    end

    def destroy
      @configuration.remove_mqtt_topic(params[:id])
      Orchestration::StackStatus.mark_config_changed!
      redirect_to datasources_mqtt_topics_path
    end

    private

    def set_configuration
      @configuration = Configuration.current
    end

    def load_topic
      @topic = @configuration.mqtt_topic(params[:id])
      redirect_to datasources_mqtt_topics_path unless @topic
    end

    def require_turbo_frame
      redirect_unless_turbo_frame(datasources_mqtt_topics_path)
    end

    def topic_params
      JSON.parse(params.require(:data))
    rescue JSON::ParserError
      head(:bad_request)
      nil
    end
  end
end
