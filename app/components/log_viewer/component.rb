module LogViewer
  class Component < ViewComponent::Base
    def initialize(service_id:, service_display_name:, log_html:)
      super()
      @service_id = service_id
      @service_display_name = service_display_name
      @log_html = log_html
    end

    private

    attr_reader :service_id, :service_display_name, :log_html
  end
end
