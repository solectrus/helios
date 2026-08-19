module Import
  class ConfigurationImporter
    class DashboardExtractor
      include Helpers

      # Container port the Rails dashboard always listens on.
      DASHBOARD_CONTAINER_PORT = 3000

      def initialize(reader, traefik_managed: false)
        @reader = reader
        @traefik_managed = traefik_managed
      end

      def section_data
        dashboard_env = service_env('dashboard')

        image_data_for('dashboard').merge(
          'co2_emission_factor' => dashboard_env['CO2_EMISSION_FACTOR'],
          'frame_ancestors' => dashboard_env['FRAME_ANCESTORS'],
          'ui_theme' => dashboard_env['UI_THEME'],
          'lockup_codeword' => dashboard_env['LOCKUP_CODEWORD'],
          'trusted_proxy_ranges' => dashboard_env['TRUSTED_PROXY_RANGES'],
          'force_ssl' => force_ssl(dashboard_env),
          'host_port' => host_port,
        ).compact
      end

      private

      # FORCE_SSL=true from a stack that runs its own reverse proxy (Apache,
      # nginx, an external Traefik). Without it the re-export would drop the
      # flag and every login through that proxy would fail. A HELIOS-managed
      # Traefik implies the flag, so it is not persisted there. Returns nil for
      # every other case so .compact drops the key.
      def force_ssl(dashboard_env)
        return nil if @traefik_managed
        return nil unless ActiveModel::Type::Boolean.new.cast(dashboard_env['FORCE_SSL'])

        true
      end

      # Host-side port the imported compose maps to the dashboard container. Returns
      # nil for the canonical 3000:3000 (HELIOS's default, no need to
      # persist) and for setups without a published port (e.g. Traefik-
      # fronted stacks). Anything else is preserved so a remapped port
      # like 3010:3000 survives the round-trip.
      def host_port
        ports = Array(@reader.service('dashboard')&.dig('ports'))
        mapping = ports.find { |p| targets_dashboard?(p) }
        return nil unless mapping

        host = published_host_port(mapping)
        host if host && host != DASHBOARD_CONTAINER_PORT.to_s
      end

      # `docker compose config --format json` normalizes short-form ports
      # to long-form hashes (target/published/protocol). Handle both so a
      # raw-YAML fallback path stays compatible too.
      def targets_dashboard?(entry)
        case entry
        when Hash then entry['target'].to_i == DASHBOARD_CONTAINER_PORT
        else entry.to_s.split(':').last == DASHBOARD_CONTAINER_PORT.to_s
        end
      end

      def published_host_port(entry)
        case entry
        when Hash then entry['published']&.to_s
        else
          host, container = entry.to_s.split(':', 2)
          container ? host : nil
        end
      end
    end
  end
end
