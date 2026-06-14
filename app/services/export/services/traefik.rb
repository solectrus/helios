module Export
  module Services
    class Traefik < Base
      # ACME resolver name HELIOS uses for its own managed Traefik. Imported
      # custom Traefik configs may name it differently (see .certresolver).
      DEFAULT_CERTRESOLVER = 'letsencrypt'.freeze

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

      # ACME resolver name the HELIOS-generated service routers
      # (dashboard/influxdb/helios) should reference in their `tls.certresolver`
      # labels. For HELIOS's own managed Traefik this is DEFAULT_CERTRESOLVER;
      # for an imported custom Traefik (captured `command`) it is read from the
      # command's `--certificatesresolvers.<name>.acme*` flag so the generated
      # labels reference a resolver that actually exists. Falls back to the
      # default when the command declares none.
      def self.certresolver(configuration)
        command = Array(configuration.reverse_proxy.command)
        return DEFAULT_CERTRESOLVER if command.blank?

        command
          .filter_map { |arg| arg.to_s[/\A--certificatesresolvers\.([^.]+)\.acme/, 1] }
          .first || DEFAULT_CERTRESOLVER
      end

      def data_directories
        managed_data_directory
      end

      def to_h
        {
          image: configuration.reverse_proxy.image.presence || DockerImages.current(:TRAEFIK),
          command: traefik_command_with_helios,
          environment: override_or(:environment, nil),
          ports: traefik_ports_with_helios,
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

      # The Traefik `command`, additively ensuring the bits HELIOS needs exist
      # while keeping every imported arg verbatim (idempotent, never appends a
      # second time):
      #   - a log level — Traefik's own default is ERROR, leaving the log empty;
      #     INFO only when no level is declared (an explicit imported level wins)
      #   - a `helios` entrypoint when HELIOS routes its UI through Traefik
      def traefik_command_with_helios
        base = override_or(:command, traefik_command)
        base += ['--log.level=INFO'] if base.none? { |arg| arg.to_s.start_with?('--log.level') }
        return base unless helios_routed?
        return base if base.any? { |arg| arg.to_s.start_with?('--entrypoints.helios.') }

        base + ["--entrypoints.helios.address=:#{Helios::HOST_PORT}"]
      end

      # Published ports, additively ensuring the HELIOS entrypoint port is bound
      # when routed through Traefik. Same additive/idempotent contract as
      # traefik_command_with_helios.
      def traefik_ports_with_helios
        base = override_or(:ports, default_ports)
        return base unless helios_routed?

        port = "#{Helios::HOST_PORT}:#{Helios::HOST_PORT}"
        base.map(&:to_s).include?(port) ? base : base + [port]
      end

      # Traefik lives under the reverse_proxy config section — override the
      # default `configuration.<service_name>` lookup used by bind_mount.
      def volume_section
        configuration.reverse_proxy
      end

      def traefik_command
        [
          # Traefik's own default log level is ERROR, which leaves
          # `docker compose logs traefik` empty during normal operation and
          # hides the startup banner. INFO surfaces startup/provider events
          # without the noise of DEBUG.
          '--log.level=INFO',
          '--providers.docker=true',
          '--providers.docker.exposedbydefault=false',
          '--entrypoints.web.address=:80',
          '--entrypoints.web.http.redirections.entrypoint.to=websecure',
          '--entrypoints.websecure.address=:443',
          *influxdb_entrypoint,
          *helios_entrypoint,
          "--certificatesresolvers.#{DEFAULT_CERTRESOLVER}.acme.tlschallenge=true",
          "--certificatesresolvers.#{DEFAULT_CERTRESOLVER}.acme.email=#{self.class.letsencrypt_email(configuration)}",
          "--certificatesresolvers.#{DEFAULT_CERTRESOLVER}.acme.storage=/letsencrypt/acme.json",
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
