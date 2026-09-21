module Surveys
  module Influxdb
    class Survey < Base
      private

      # The static JSON describes the default deployment: publishing a plain
      # host port on the LAN. Behind a reverse proxy the same toggle means
      # something else, and it leads to another address, so the copy has to say
      # what actually happens in the mode that is running.
      def customize!(data)
        element = find_element(data, 'publish_port')
        return unless element

        if managed_traefik?
          element['title'] = managed_title
          element['description'] = managed_description
        elsif (url = external_url)
          element['title'] = external_title
          element['description'] = external_description(url)
        end
      end

      # Behind the HELIOS-managed Traefik the toggle routes InfluxDB through it
      # (HTTPS, public domain, dedicated entrypoint; see
      # Export::Services::Influxdb) instead of publishing a plain host port.
      def managed_title
        self.class.localized(
          en: 'Make InfluxDB reachable via Traefik',
          de: 'InfluxDB über Traefik erreichbar machen',
        )
      end

      def managed_description
        self.class.localized(
          en: 'Routes InfluxDB through Traefik with HTTPS. InfluxDB is then publicly reachable at ' \
              "#{managed_url}, for example for the built-in InfluxDB web interface or external tools. " \
              'If needed, access can be restricted with a firewall.',
          de: 'Routet InfluxDB per HTTPS über Traefik. InfluxDB ist dann öffentlich unter ' \
              "#{managed_url} erreichbar, etwa für die eingebaute Weboberfläche von InfluxDB oder " \
              'externe Tools. Falls nötig, lässt sich der Zugriff per Firewall einschränken.',
        )
      end

      # Behind an external proxy the toggle opens the way that proxy reaches
      # InfluxDB. Without it the proxy has nothing to reach, and the generated
      # Traefik file leaves InfluxDB out (see Export::TraefikConfig).
      def external_title
        self.class.localized(
          en: 'Make InfluxDB reachable through the proxy',
          de: 'InfluxDB über den Proxy erreichbar machen',
        )
      end

      # What the toggle opens depends on how the proxy reaches the stack: a
      # host port it routes to, or a route on the shared network it is on
      # (see Configuration#reverse_proxy_on_shared_network?).
      def external_description(url)
        opens = shared_network? ? shared_network_opens : host_port_opens
        route = shared_network? && configuration.reverse_proxy_labels? ? '' : route_note

        self.class.localized(
          en: "#{opens[:en]} Intended address: #{url}.#{" #{route[:en]}" if route.present?}",
          de: "#{opens[:de]} Vorgesehene Adresse: #{url}.#{" #{route[:de]}" if route.present?}",
        )
      end

      def host_port_opens
        {
          en: 'Publishes the port on the host so the external proxy can reach InfluxDB, for example ' \
              'for the built-in InfluxDB web interface or external tools.',
          de: 'Gibt den Port auf dem Host frei, damit der externe Proxy die InfluxDB erreicht, etwa für ' \
              'die eingebaute Weboberfläche von InfluxDB oder externe Tools.',
        }
      end

      def shared_network_opens
        {
          en: 'Lets the external proxy reach InfluxDB over the shared network, for example for the ' \
              'built-in InfluxDB web interface or external tools. No port is published on the host.',
          de: 'Lässt den externen Proxy die InfluxDB über das gemeinsame Netzwerk erreichen, etwa für ' \
              'die eingebaute Weboberfläche von InfluxDB oder externe Tools. Auf dem Host wird kein ' \
              'Port freigegeben.',
        }
      end

      def route_note
        {
          en: 'The route for it has to be set up in the proxy.',
          de: 'Die passende Route muss im Proxy eingerichtet werden.',
        }
      end

      def shared_network?
        configuration.reverse_proxy_on_shared_network?
      end

      # Mirrors the export-side condition (Export::Services::Influxdb
      # .traefik_managed_routing?) minus the exposure flag, which is the very
      # toggle this copy describes. An imported custom Traefik (captured
      # `command`) keeps the direct host port, so the default LAN copy stays.
      def managed_traefik?
        configuration.reverse_proxy_managed? && configuration.reverse_proxy.command.blank?
      end

      def managed_url
        domain = configuration.public_host
        port = Export::Services::Influxdb.host_port(configuration)
        "https://#{domain}:#{port}"
      end

      # The address the external proxy is meant to answer on. Built from the
      # subdomain the export routes InfluxDB at, so the copy and the route
      # cannot drift apart. Not taken from Export::PublicUrl: that one answers
      # for a service already routed, and this copy describes the toggle that
      # routes it. It stays empty while nothing names the machine, and the
      # default copy then holds.
      def external_url
        return unless configuration.reverse_proxy_external?
        return if configuration.public_host.blank?

        "https://#{Export::Services::Influxdb.proxy_subdomain}.#{configuration.public_host}"
      end

      def configuration
        @configuration ||= Configuration.current
      end
    end
  end
end
