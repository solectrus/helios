module Import
  class ConfigurationImporter
    # Captures per-service compose-key overrides for managed services (ADR-0015).
    # Currently scoped to `traefik.*` labels on managed services — the only
    # divergence shape observed often enough in fixtures to need automated
    # rescue. Other allowlist keys (ports, volumes, environment) are left to
    # the user via the UI for now.
    #
    # Two recovery paths:
    #
    #   1. Non-dashboard managed services keep their imported `traefik.*`
    #      labels verbatim. HELIOS regenerates the service definition but no
    #      longer owns its routing — the donor's custom router/entrypoint
    #      survives 1:1.
    #
    #   2. The dashboard's labels are split: HELIOS regenerates its canonical
    #      router (rule/entrypoints/tls.certresolver/services.dashboard.*),
    #      so those labels are dropped from the override. Anything else
    #      (typically `traefik.http.middlewares.<name>.*` for rate limits,
    #      headers, basic auth, ...) survives as a dashboard override.
    class ServiceOverridesExtractor
      include Helpers

      # Label keys HELIOS regenerates for the dashboard's own router. Router
      # name is variable in the wild ("dashboard", "app-solectrus", ...), so
      # we match by structure rather than by exact name.
      DASHBOARD_HELIOS_LABEL_PATTERNS = [
        /\Atraefik\.enable\b/,
        /\Atraefik\.http\.routers\.[^.]+\.rule\b/,
        /\Atraefik\.http\.routers\.[^.]+\.entrypoints\b/,
        /\Atraefik\.http\.routers\.[^.]+\.tls(\.certresolver)?\b/,
        /\Atraefik\.http\.services\.[^.]+\.loadbalancer\.server\.port\b/,
      ].freeze

      def initialize(reader)
        @reader = reader
      end

      def section_data
        managed_services_in_compose.each_with_object({}) do |name, result|
          labels = override_labels_for(name)
          result[name] = { 'labels' => labels } if labels.any?
        end.presence
      end

      private

      def managed_services_in_compose
        StackReader::SERVICE_IMAGE_PREFIXES.keys.select { |name| @reader.services.key?(name) }
      end

      # Read labels from the unresolved raw compose so the donor's ordering
      # is preserved. The resolved view from `docker compose config` would
      # alphabetize them, which round-trips noisily when exporting.
      def override_labels_for(name)
        labels = traefik_labels_of(@reader.raw_compose.dig('services', name))
        return [] if labels.empty?

        name == 'dashboard' ? labels.reject { |l| helios_dashboard_label?(l) } : labels
      end

      def traefik_labels_of(service_config)
        labels = service_config&.dig('labels')
        case labels
        when Array then labels.select { |l| l.to_s.start_with?('traefik.') }
        when Hash
          labels.select { |k, _| k.to_s.start_with?('traefik.') }.map { |k, v| "#{k}=#{v}" }
        else []
        end
      end

      def helios_dashboard_label?(label)
        DASHBOARD_HELIOS_LABEL_PATTERNS.any? { |pattern| label.to_s.match?(pattern) }
      end
    end
  end
end
