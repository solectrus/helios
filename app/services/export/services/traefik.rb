module Export
  module Services
    class Traefik < Base
      def self.service_name
        'traefik'
      end

      def self.config_keys
        ['reverse_proxy']
      end

      def self.comment
        'Traefik — Reverse proxy with automatic HTTPS'
      end

      def self.enabled?(configuration)
        !configuration.collectors_only? && configuration.reverse_proxy.app_domain.present?
      end

      def self.letsencrypt_email(configuration)
        configuration.reverse_proxy.letsencrypt_email.presence ||
          "webmaster@#{configuration.reverse_proxy.app_domain}"
      end

      def data_directories
        managed_data_directory
      end

      def to_h
        {
          image: configuration.reverse_proxy.image.presence || DockerImages.current(:TRAEFIK),
          command: traefik_command,
          ports: %w[80:80 443:443],
          volumes: [
            '/var/run/docker.sock:/var/run/docker.sock:ro',
            bind_mount('/letsencrypt'),
          ],
          restart: 'unless-stopped',
        }
      end

      private

      # Traefik lives under the reverse_proxy config section — override the
      # default `configuration.<service_name>` lookup used by bind_mount.
      def volume_section
        configuration.reverse_proxy
      end

      def traefik_command
        [
          '--providers.docker=true',
          '--providers.docker.exposedbydefault=false',
          '--entrypoints.web.address=:80',
          '--entrypoints.web.http.redirections.entrypoint.to=websecure',
          '--entrypoints.websecure.address=:443',
          '--certificatesresolvers.letsencrypt.acme.tlschallenge=true',
          "--certificatesresolvers.letsencrypt.acme.email=#{self.class.letsencrypt_email(configuration)}",
          '--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json',
        ]
      end
    end
  end
end
