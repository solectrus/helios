module Services
  class BatchesController < ApplicationController
    before_action :require_configuration_complete, only: :create
    before_action :require_proxy_network, only: :create

    # POST /services/batch - Start all services (also recreates containers
    # whose config has changed, since `docker compose up` is idempotent).
    #
    # An ordinary start leaves HELIOS running, so the screen stays. Where the
    # host port of HELIOS moves it cannot: only a run that carries HELIOS hands
    # that port over (see Orchestration::SelfPorts). HELIOS then ends with the
    # run, so the answer is the restart screen instead of a row update.
    def create
      Orchestration::StackStatus.mark_starting!
      return start_including_self if self_ports_drifted?

      ComposeJob.perform_later(:up)

      respond_with_pending_status(:starting, action: :up) do |_, container|
        !container&.running?
      end
    end

    # DELETE /services/batch - Stop all services
    def destroy
      Orchestration::StackStatus.mark_stopping!
      ComposeJob.perform_later(:down)
      respond_with_pending_status(:stopping, action: :down) do |_, container|
        container&.running?
      end
    end

    private

    # The stack that owns the shared network is not this one, so the network
    # can go between the save that named it and this start. Compose would
    # refuse the whole run, and where that run is the one that hands port 3999
    # over (see Orchestration::SelfPorts), it would take the interface with it.
    def require_proxy_network
      name = Orchestration::ProxyNetwork.missing
      return unless name

      flash[:alert] = t('services.errors.unknown_proxy_network', network: name)
      redirect_to services_path
    end

    def start_including_self
      ComposeJob.perform_later(:self_converge)
      redirect_to restarting_path(boot_id: Rails.application.config.boot_id, moved: true)
    end

    # The compose file is what the drift is read from, and the job that runs
    # the start is what usually writes it. So bring it up to date here, the
    # same way the services screen does before it renders a row.
    def self_ports_drifted?
      Export::Builder.new(Configuration.current).write_if_stale!
      Orchestration::SelfPorts.drifted?
    end

    def respond_with_pending_status(status, action:, &)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream_updates(status, action, &)
        end
        format.html { redirect_to services_path }
      end
    end

    def turbo_stream_updates(status, action, &)
      service_row_updates(action, &) + [status_bar_update(status)]
    end

    def service_row_updates(action, &)
      services_to_update.map do |compose_service|
        service_row_update(compose_service, action, &)
      end
    end

    def service_row_update(compose_service, action)
      container = containers_by_service[compose_service.name]
      pending = yield(compose_service, container)
      if pending
        Orchestration::PendingOperations.set(compose_service.name, action)
      end
      turbo_stream.replace(
        "service-#{compose_service.name}",
        ServiceRow::Component.new(
          compose_service:, container:, pending:, lazy: false,
        ),
        method: :morph,
      )
    end

    def status_bar_update(status)
      turbo_stream.replace('status-bar', StatusBar::Component.new(status:), method: :morph)
    end

    def services_to_update
      @services_to_update ||= Compose.load.services.reject(&:helios?)
    end

    def containers_by_service
      @containers_by_service ||=
        Orchestration::Container.all.index_by(&:service_name)
    end
  end
end
