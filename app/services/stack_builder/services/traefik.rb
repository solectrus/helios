class StackBuilder
  module Services
    class Traefik < Base
      def self.service_name
        'traefik'
      end

      def self.comment
        'Reverse proxy with automatic HTTPS'
      end

      def self.enabled?(configuration)
        rp = configuration.reverse_proxy
        rp.enabled == true && rp.app_domain.present?
      end

      def self.letsencrypt_email(configuration)
        configuration.reverse_proxy.letsencrypt_email.presence ||
          "webmaster@#{configuration.reverse_proxy.app_domain}"
      end

      def self.data_directories
        ['traefik']
      end

      def to_h
        {
          image: 'traefik:v3',
          command: traefik_command,
          ports: %w[80:80 443:443],
          volumes: [
            '/var/run/docker.sock:/var/run/docker.sock:ro',
            './traefik:/letsencrypt',
          ],
          restart: 'unless-stopped',
        }
      end

      private

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
