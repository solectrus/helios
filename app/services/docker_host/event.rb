module DockerHost
  class Event
    RELEVANT_ACTIONS = %w[start stop die health_status].freeze

    attr_reader :raw_event

    def initialize(raw_event)
      @raw_event = raw_event
    end

    delegate :type, :action, to: :raw_event

    def container?
      type == 'container'
    end

    def service_name
      raw_event.actor&.attributes&.dig('com.docker.compose.service')
    end

    def relevant?
      container? && service_name.present? && relevant_action?
    end

    def relevant_action?
      RELEVANT_ACTIONS.include?(action) ||
        action.to_s.start_with?('health_status')
    end

    def to_h
      { type: type, action: action, service_name: service_name }
    end

    def inspect
      "#<DockerHost::Event #{type}:#{action} service=#{service_name}>"
    end
  end
end
