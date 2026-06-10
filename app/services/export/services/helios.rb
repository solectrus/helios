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

      # True when HELIOS routes its own UI through Traefik (HTTPS, same domain,
      # dedicated :3999 entrypoint) instead of publishing a plain host port.
      # Holds whenever Traefik is active — including an imported custom Traefik:
      # HELIOS owns its own UI, so it injects the `helios` entrypoint into that
      # command (see Traefik#traefik_command_with_helios) and derives the
      # certresolver from it (Traefik.certresolver) rather than leaving the UI
      # on plain HTTP.
      def self.traefik_managed_routing?(configuration)
        Traefik.enabled?(configuration)
      end

      def to_h
        config = {
          image: configuration.helios.image.presence || DockerImages.current(:HELIOS),
          environment: helios_environment,
          volumes: VOLUMES,
          restart: 'unless-stopped',
        }

        if traefik_managed_routing?
          # Behind Traefik: route the UI through it (HTTPS, same domain,
          # dedicated :3999 entrypoint) instead of a plain-HTTP host port. Any
          # `helios` router labels carried in via service_overrides (a re-import
          # of HELIOS's own output) dedupe against these generated ones.
          config[:labels] = traefik_labels
        else
          config[:ports] = ["#{HOST_PORT}:#{CONTAINER_PORT}"]
        end

        config
      end

      private

      def traefik_managed_routing?
        self.class.traefik_managed_routing?(configuration)
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
          "traefik.http.routers.helios.tls.certresolver=#{Traefik.certresolver(configuration)}",
          "traefik.http.services.helios.loadbalancer.server.port=#{CONTAINER_PORT}",
        ]
      end
    end
  end
end
