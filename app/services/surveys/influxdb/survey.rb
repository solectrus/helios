module Surveys
  module Influxdb
    class Survey < Base
      private

      # The static JSON describes the default deployment: publishing a plain
      # host port on the LAN. Behind a HELIOS-managed Traefik the same toggle
      # routes InfluxDB through Traefik instead (HTTPS, public domain, dedicated
      # entrypoint; see Export::Services::Influxdb), so the copy must say what
      # actually happens, including the resulting URL.
      def customize!(data)
        return unless managed_traefik?

        element = find_element(data, 'publish_port')
        return unless element

        element['title'] = self.class.localized(
          en: 'Make InfluxDB reachable via Traefik',
          de: 'InfluxDB über Traefik erreichbar machen',
        )
        element['description'] = self.class.localized(
          en: 'Routes InfluxDB through Traefik with HTTPS. InfluxDB is then publicly reachable at ' \
              "#{influxdb_url}, for example for the built-in InfluxDB web interface or external tools. " \
              'If needed, access can be restricted with a firewall.',
          de: 'Routet InfluxDB per HTTPS über Traefik. InfluxDB ist dann öffentlich unter ' \
              "#{influxdb_url} erreichbar, etwa für die eingebaute Weboberfläche von InfluxDB oder " \
              'externe Tools. Falls nötig, lässt sich der Zugriff per Firewall einschränken.',
        )
      end

      # Mirrors the export-side condition (Export::Services::Influxdb
      # .traefik_managed_routing?) minus the exposure flag, which is the very
      # toggle this copy describes. An imported custom Traefik (captured
      # `command`) keeps the direct host port, so the default LAN copy stays.
      def managed_traefik?
        config = Configuration.current
        config.reverse_proxy_managed? && config.reverse_proxy.command.blank?
      end

      def influxdb_url
        config = Configuration.current
        domain = config.reverse_proxy.app_domain
        port = Export::Services::Influxdb.host_port(config)
        "https://#{domain}:#{port}"
      end
    end
  end
end
