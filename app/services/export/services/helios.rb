module Export
  module Services
    class Helios < Base
      ENVIRONMENT = %w[
        TZ
        ADMIN_PASSWORD
        SECRET_KEY_BASE
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

      def to_h
        {
          image: configuration.helios.image.presence || DockerImages.current(:HELIOS),
          environment: ENVIRONMENT,
          volumes: [
            '.:/data',
            '/var/run/docker.sock:/var/run/docker.sock',
            # Host cgroup, read-only: lets HostStats report the Docker host's
            # real RAM/CPU usage. A HELIOS container nested in a Proxmox LXC
            # otherwise reads the physical node's /proc, not the LXC's. No-op
            # on bare-metal/VM hosts, where /proc is already accurate.
            '/sys/fs/cgroup:/host/sys/fs/cgroup:ro',
          ],
          ports: ['3999:3000'],
          restart: 'unless-stopped',
        }
      end
    end
  end
end
