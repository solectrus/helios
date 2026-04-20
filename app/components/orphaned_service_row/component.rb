module OrphanedServiceRow
  class Component < ViewComponent::Base
    attr_reader :container, :pending

    def initialize(container:, pending: false)
      super()
      @container = container
      @pending = pending
    end

    def dom_id
      "service-#{service_name}"
    end

    delegate :service_name, to: :container

    def display_name
      Compose::Service.display_name_for(service_name)
    end

    def stop_disabled?
      pending || !container.stoppable?
    end

    def status_indicator_class
      if pending
        'loading loading-spinner loading-xs text-primary'
      else
        "inline-block w-3 h-3 rounded-full #{container.running? ? 'bg-success' : 'bg-neutral'}"
      end
    end

    def status_label
      pending ? t('.processing') : t('.orphaned')
    end
  end
end
