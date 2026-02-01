module Services
  class VersionsController < BaseController
    def show
      render ServiceVersion::Component.new(
        service_name:,
        version: container&.version,
      )
    end
  end
end
