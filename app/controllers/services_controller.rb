class ServicesController < ApplicationController
  def index
    # Before setup is completed there is no stack to manage — index.html.erb
    # renders an empty state instead of the (helios-only) service list.
    return unless (@setup_completed = Configuration.current.setup_completed?)

    Export::Builder.new(Configuration.current).write_if_stale!
    compose = Compose.load
    @compose_services = compose.services.sorted

    # Preload containers on Turbo Frame requests (tab switches) to avoid skeleton flicker.
    # On full page loads (initial visit, refresh) use lazy loading for faster first paint.
    if turbo_frame_request?
      all_containers = Orchestration::Container.all
      @containers = all_containers.index_by(&:service_name)
    end

    @orphaned_containers = Orchestration::OrphanedServices.detect(
      compose_services: compose.services,
      containers: all_containers,
    )
  rescue Orchestration::ConnectionError
    @containers = nil
    @orphaned_containers = nil
  end

  # DELETE /services/:id
  # Removes a service row. The kind of removal depends on the service:
  #   - unmanaged service  → deleted from config.yaml and torn down
  #   - orphaned container  → stopped and removed
  #   - managed service     → rejected (owned by HELIOS)
  def destroy
    if Configuration.current.unmanaged_service?(service_id)
      destroy_unmanaged_service
    elsif compose_file.services.exists?(service_id)
      head :forbidden # managed service — owned by HELIOS, not removable
    elsif container&.stoppable?
      destroy_orphaned_container
    else
      redirect_to services_path
    end
  end

  private

  def service_id
    params[:id]
  end

  def container
    @container ||= Orchestration::Container.find(service_id)
  end

  def compose_file
    @compose_file ||= Compose.load
  end

  def destroy_unmanaged_service
    Orchestration::PendingOperations.set(service_id, :remove)
    ServiceRemovalJob.perform_later(service_id)
    render_pending_row ServiceRow::Component.new(
      compose_service: compose_file.services.find(service_id),
      container:,
      pending: true,
      lazy: false,
    )
  end

  def destroy_orphaned_container
    # Claims the name, so a click during a running sweep does not queue a
    # second job — and the sweep keeps its claim until this removal is done.
    Orchestration::OrphanedServices.remove!(service_id)
    render_pending_row OrphanedServiceRow::Component.new(container:, pending: true)
  end

  def render_pending_row(component)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream:
          turbo_stream.replace("service-#{service_id}", component, method: :morph)
      end
      format.html { redirect_to services_path }
    end
  end
end
