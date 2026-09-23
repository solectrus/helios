module Orchestration
  class Event
    # pause/unpause are what an update pause looks like from Docker's side
    # (see Orchestration::UpdatePause): the container is never stopped, so
    # without them the row would keep reporting the service as running.
    RELEVANT_ACTIONS = %w[create start stop die destroy pause unpause].freeze
    HELIOS_OPERATION_CONTAINER_NAMES = [
      BackupRunner::CONTAINER_NAME,
      RestoreRunner::CONTAINER_NAME,
    ].freeze

    def initialize(raw_event)
      @raw_event = raw_event
    end

    delegate :type, :action, to: :raw_event

    def relevant?
      container? && service_name.present? && relevant_action?
    end

    # Detached backup/restore containers run outside Compose, so they have no
    # `com.docker.compose.service` label. Match them by container name instead
    # so the status bar can react to their lifecycle.
    def helios_operation?
      container? && relevant_action? && HELIOS_OPERATION_CONTAINER_NAMES.include?(container_name)
    end

    def service_name
      attribute(COMPOSE_SERVICE_LABEL)
    end

    # Config hash of the service container Docker just created. A one-off
    # container (`docker compose run`) leaves the service container as it
    # is, so it yields nil like every other event.
    def created_config_hash
      return unless action == 'create'
      return if attribute(COMPOSE_ONEOFF_LABEL) == 'True'

      attribute(COMPOSE_CONFIG_HASH_LABEL)
    end

    def container_name
      attribute('name')
    end

    def to_h
      { type: type, action: action, service_name: service_name }
    end

    def inspect
      "#<Orchestration::Event #{type}:#{action} service=#{service_name}>"
    end

    private

    attr_reader :raw_event

    def attribute(name)
      raw_event.actor&.attributes&.dig(name)
    end

    def container?
      type == 'container'
    end

    def relevant_action?
      RELEVANT_ACTIONS.include?(action) ||
        action.to_s.start_with?('health_status')
    end
  end
end
