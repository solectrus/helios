module Export
  module Services
    class Helios < Base
      CONTAINER_PORT = 3000
      HOST_PORT = 3999

      ENVIRONMENT = %w[
        TZ
        ADMIN_PASSWORD
        SECRET_KEY_BASE
      ].freeze

      VOLUMES = [
        '.:/data',
        '/var/run/docker.sock:/var/run/docker.sock',
        # Host cgroup, read-only: lets HostStats report the Docker host's
        # real RAM/CPU usage. A HELIOS container nested in a Proxmox LXC
        # otherwise reads the physical node's /proc, not the LXC's. No-op
        # on bare-metal/VM hosts, where /proc is already accurate.
        '/sys/fs/cgroup:/host/sys/fs/cgroup:ro',
      ].freeze

      def self.service_name
        'helios'
      end

      def self.comment
        'HELIOS — Configuration management UI'
      end

      def self.enabled?(_configuration)
        !Rails.env.development?
      end

      # True when HELIOS routes its own UI through a HELIOS-owned Traefik
      # (HTTPS, same domain, dedicated entrypoint) instead of publishing a
      # direct host port. An imported custom Traefik (captured `command`) is
      # left alone — we cannot assume it declares a `helios` entrypoint, so the
      # UI keeps its plain host port there.
      def self.traefik_managed_routing?(configuration)
        Traefik.enabled?(configuration) && configuration.reverse_proxy.command.blank?
      end

      def to_h
        config = {
          image: configuration.helios.image.presence || DockerImages.current(:HELIOS),
          environment: helios_environment,
          volumes: VOLUMES,
          restart: 'unless-stopped',
        }

        if traefik_managed_routing?
          # Behind a HELIOS-owned Traefik: route the UI through it (HTTPS, same
          # domain, dedicated :3999 entrypoint) instead of a plain-HTTP host port.
          config[:labels] = traefik_labels
        elsif !traefik_routes_helios?
          config[:ports] = ["#{HOST_PORT}:#{CONTAINER_PORT}"]
        end
        # Remaining case: an imported Traefik already declares a `helios`
        # entrypoint (typically a re-import of HELIOS's own output) — its labels
        # come in via service_overrides, and no direct port is published so 3999
        # isn't bound twice.

        config
      end

      private

      def traefik_managed_routing?
        self.class.traefik_managed_routing?(configuration)
      end

      # Whether an imported custom Traefik (captured `command`) declares a
      # dedicated `helios` entrypoint and therefore owns host port 3999. The
      # managed (blank-command) case is handled by traefik_managed_routing?.
      def traefik_routes_helios?
        return false unless Traefik.enabled?(configuration)

        Array(configuration.reverse_proxy.command)
          .any? { |arg| arg.to_s.start_with?('--entrypoints.helios.') }
      end

      # FORCE_SSL makes HELIOS set secure cookies and emit https URLs when it
      # sits behind Traefik's TLS — the same switch the dashboard uses. Left out
      # of the direct-port deployment, which is plain HTTP.
      def helios_environment
        env = ENVIRONMENT.dup
        env << 'FORCE_SSL=true' if traefik_managed_routing?
        env
      end

      def traefik_labels
        domain = configuration.reverse_proxy.app_domain
        [
          'traefik.enable=true',
          "traefik.http.routers.helios.rule=Host(`#{domain}`)",
          'traefik.http.routers.helios.entrypoints=helios',
          'traefik.http.routers.helios.tls.certresolver=letsencrypt',
          "traefik.http.services.helios.loadbalancer.server.port=#{CONTAINER_PORT}",
        ]
      end
    end
  end
end
