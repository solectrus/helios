module Export
  module Services
    class Traefik < Base
      def self.service_name
        'traefik'
      end

      def self.config_keys
        ['reverse_proxy']
      end

      def self.volume_env_key
        'TRAEFIK_VOLUME_PATH'
      end

      def self.comment
        'Traefik — Reverse proxy with automatic HTTPS'
      end

      def self.enabled?(configuration)
        configuration.reverse_proxy_managed?
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
          command: override_or(:command, traefik_command),
          environment: override_or(:environment, nil),
          ports: override_or(:ports, default_ports),
          volumes: override_or(:volumes, [
                                 '/var/run/docker.sock:/var/run/docker.sock:ro',
                                 bind_mount('/letsencrypt'),
                               ]),
          labels: override_or(:labels, nil),
          restart: override_or(:restart, 'unless-stopped'),
        }.compact
      end

      private

      # Use the imported value when present, falling back to HELIOS's
      # generated default. Keeps quirky in-the-wild Traefik setups
      # (custom entrypoints, resolver names, extra ports, label sets)
      # round-tripping cleanly.
      def override_or(key, default)
        configuration.reverse_proxy[key.to_s].presence || default
      end

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
          *influxdb_entrypoint,
          *helios_entrypoint,
          '--certificatesresolvers.letsencrypt.acme.tlschallenge=true',
          "--certificatesresolvers.letsencrypt.acme.email=#{self.class.letsencrypt_email(configuration)}",
          '--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json',
        ]
      end

      # Default published ports — adds the InfluxDB and HELIOS entrypoint ports
      # when those services are routed through Traefik (see Services::Influxdb /
      # Services::Helios).
      def default_ports
        ports = %w[80:80 443:443]
        ports << "#{influxdb_host_port}:#{influxdb_host_port}" if influxdb_routed?
        ports << "#{Helios::HOST_PORT}:#{Helios::HOST_PORT}" if helios_routed?
        ports
      end

      # Dedicated entrypoint for the InfluxDB HTTP API/UI, terminating TLS
      # so external access matches the dashboard (HTTPS, same domain).
      def influxdb_entrypoint
        return [] unless influxdb_routed?

        ["--entrypoints.influxdb.address=:#{influxdb_host_port}"]
      end

      def influxdb_routed?
        Influxdb.traefik_managed_routing?(configuration)
      end

      def influxdb_host_port
        Influxdb.host_port(configuration)
      end

      # Dedicated entrypoint for the HELIOS management UI, terminating TLS so it
      # is reached over HTTPS on the same domain (https://<app_domain>:3999).
      def helios_entrypoint
        return [] unless helios_routed?

        ["--entrypoints.helios.address=:#{Helios::HOST_PORT}"]
      end

      def helios_routed?
        Helios.traefik_managed_routing?(configuration)
      end
    end
  end
end
