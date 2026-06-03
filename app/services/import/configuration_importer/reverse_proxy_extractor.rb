module Import
  class ConfigurationImporter
    class ReverseProxyExtractor
      include Helpers

      # Verbatim Traefik service keys captured as pass-through overrides.
      # When set, the exporter emits these instead of HELIOS's generated
      # defaults — covers in-the-wild Traefik configs with custom entrypoints,
      # resolver names, ports, or labels that don't fit the managed shape.
      PASSTHROUGH_KEYS = %w[command ports volumes restart labels environment].freeze

      # Match any traefik.http.routers.<name>.rule label, not just the
      # canonical "dashboard" router. Real-world configs use names like
      # "app-solectrus" or arbitrary user-chosen identifiers.
      ROUTER_RULE_KEY = /\Atraefik\.http\.routers\.[^.]+\.rule\b/

      # Managed services that publish host ports in the "external Traefik" mode.
      # HELIOS binds them all to the same IP, so reading it from any one is enough.
      PORT_PUBLISHERS = %w[dashboard influxdb ingest helios].freeze

      # Wildcard bind addresses are equivalent to "no explicit bind" — HELIOS
      # already defaults to all interfaces, so they don't set a bind_ip.
      WILDCARD_IPS = %w[0.0.0.0 ::].freeze

      def initialize(reader, volume_resolver)
        @reader = reader
        @volume_resolver = volume_resolver
      end

      def section_data
        data = traefik_data || {}
        ip = bind_ip
        data['bind_ip'] = ip if ip.present?
        data.presence
      end

      private

      def traefik_data
        return nil unless @reader.services.key?('traefik')

        domain = extract_domain_from_dashboard_labels
        return nil unless domain

        {
          'app_domain' => domain,
          'letsencrypt_email' => @reader.raw_env['LETSENCRYPT_EMAIL'],
          'image' => @reader.service('traefik')&.dig('image'),
        }
          .merge(passthrough_data)
          .merge(@volume_resolver.path_data('reverse_proxy'))
          .compact
      end

      # The host IP a published port is bound to (external-Traefik mode), read
      # from any managed publisher's port mapping. Returns nil for wildcard
      # binds, which carry no information HELIOS needs to persist.
      def bind_ip
        PORT_PUBLISHERS
          .flat_map { |name| Array(@reader.service(name)&.dig('ports')) }
          .filter_map { |entry| host_ip(entry) }
          .first
      end

      def host_ip(entry)
        ip =
          if entry.is_a?(Hash)
            entry['host_ip']
          else
            parts = entry.to_s.split(':', 3)
            parts.first if parts.size == 3
          end

        ip if ip.present? && WILDCARD_IPS.exclude?(ip)
      end

      def passthrough_data
        # Use the raw (unresolved) compose so ports/volumes stay in their
        # original string shorthand ("80:80", "./traefik:/letsencrypt")
        # instead of `docker compose config`'s expanded object form, which
        # would balloon config.yaml and bake in temp absolute paths.
        traefik = @reader.raw_compose.dig('services', 'traefik') || {}

        # Only capture overrides when the imported Traefik sets a custom
        # `command` — that's the strongest signal it diverges from HELIOS's
        # managed shape (custom entrypoints, resolver name, ACME options).
        # Without a custom command we leave the canonical defaults intact
        # so config.yaml stays clean for the standard case.
        return {} if traefik['command'].blank?

        PASSTHROUGH_KEYS.each_with_object({}) do |key, data|
          value = traefik[key]
          data[key] = value if value.present?
        end
      end

      def extract_domain_from_dashboard_labels
        rule_value = find_traefik_rule_label
        match = rule_value&.match(/Host\(`([^`]+)`\)/)
        match && match[1]
      end

      def find_traefik_rule_label
        labels = @reader.service('dashboard')&.dig('labels') || {}

        if labels.is_a?(Hash)
          labels.find { |k, _| k.match?(ROUTER_RULE_KEY) }&.last
        else
          labels.find { |v| v.to_s.match?(ROUTER_RULE_KEY) }
        end
      end
    end
  end
end
