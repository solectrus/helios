module ServiceRow
  # Computes the target of the row's "Open" button. Mixed into the component to
  # keep the endpoint logic in one place.
  module Openable
    def public_port
      container&.public_port || compose_service.public_port
    end

    # Where the "Open" button should send the user, or nil when the service has
    # no browsable endpoint. Returns either an absolute :url (built server-side
    # from the public domain, when behind a reverse proxy) or a :port (opened
    # client-side at the current hostname, so it works regardless of how HELIOS
    # itself is being accessed).
    #
    # Traefik is excluded: it is the reverse proxy, its published 80/443 ports
    # are not a destination of their own.
    def open_endpoint
      return if service_name == 'traefik'

      url = Export::PublicUrl.build(Configuration.current, service_name, published: public_port.present?)
      if url
        { url: }
      elsif public_port
        { port: public_port }
      end
    end
  end
end
