module ServiceRow
  # Computes the target of the row's "Open" button. Mixed into the component to
  # keep the endpoint logic in one place.
  module Openable
    def public_port
      container&.public_port || compose_service.public_port
    end

    def open_endpoint
      Export::OpenEndpoint.resolve(service_name:, public_port:)
    end
  end
end
