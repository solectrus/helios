module Services
  class BaseController < ApplicationController
    private

    def service_name
      params[:service_id]
    end

    def container
      @container ||= Orchestration::Container.find(service_name)
    end

    def compose_service
      @compose_service ||= Compose.load.services.find(service_name)
    end

    def helios?
      compose_service&.helios?
    end
  end
end
