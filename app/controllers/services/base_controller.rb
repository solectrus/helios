module Services
  class BaseController < ApplicationController
    private

    def service_name
      params[:service_id]
    end

    def container
      @container ||= DockerHost::Container.find(service_name)
    end

    def compose_service
      @compose_service ||= Compose.load.services.find(service_name)
    end
  end
end
