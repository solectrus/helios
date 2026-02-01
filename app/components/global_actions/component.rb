module GlobalActions
  class Component < ViewComponent::Base
    attr_reader :stopped_services, :any_running

    def initialize(stopped_services:, any_running:)
      super()
      @stopped_services = stopped_services
      @any_running = any_running
    end

    def batch_path
      '/services/batch'
    end

    def start_disabled?
      stopped_services.empty?
    end

    def stop_disabled?
      !any_running
    end
  end
end
