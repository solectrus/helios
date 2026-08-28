module Export
  module Services
    class Traefik < Base
      # ACME resolver name HELIOS uses for its own managed Traefik. Imported
      # custom Traefik configs may name it differently (see .certresolver).
      DEFAULT_CERTRESOLVER = 'letsencrypt'.freeze

      # First Traefik version that knows `aliasHeadersStrategy`. Older versions
      # abort the start with "field not found", so the flag must never reach
      # them (see alias_headers_supported?).
      ALIAS_HEADERS_MIN_VERSION = Gem::Version.new('3.7')

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
          image: traefik_image,
          command: effective_traefik_command,
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
      # second time).
      def effective_traefik_command
        command = override_or(:command, traefik_command)
        command = with_log_level(command)
        command = with_helios_entrypoint(command)
        with_alias_headers_strategy(command)
      end

      # Traefik's own default log level is ERROR, which leaves the log empty.
      # INFO only when no level is declared — an explicit imported level wins.
      def with_log_level(command)
        return command if command.any? { |arg| arg.to_s.start_with?('--log.level') }

        command + ['--log.level=INFO']
      end

      def with_helios_entrypoint(command)
        return command unless helios_routed?
        return command if command.any? { |arg| arg.to_s.start_with?('--entrypoints.helios.') }

        command + ["--entrypoints.helios.address=:#{Helios::HOST_PORT}"]
      end

      # Header names that differ only in their separators (`X_Forwarded_For` vs
      # `X-Forwarded-For`) stay distinct for Traefik, but Rack derives its env
      # keys from them and folds both onto `HTTP_X_FORWARDED_FOR`. Traefik
      # forwards such aliases unchanged by default and warns about it for every
      # entrypoint at startup, so drop them at the edge.
      #
      # A Traefik too old for the flag refuses to start when it sees it, so on
      # those versions HELIOS strips it back out too — a re-imported command can
      # carry it in from a later version the user has since downgraded from.
      def with_alias_headers_strategy(command)
        return command.reject { |arg| alias_headers_strategy?(arg) } unless alias_headers_supported?

        entrypoints(command).reduce(command) do |result, name|
          next result if result.any? { |arg| alias_headers_strategy?(arg, name) }

          result + ["--entrypoints.#{name}.http.aliasHeadersStrategy=delete"]
        end
      end

      # Matches the flag for one entrypoint, or for any of them when no name is
      # given. Traefik reads its flag names case-insensitively, so do the same.
      def alias_headers_strategy?(arg, entrypoint = nil)
        name = entrypoint ? Regexp.escape(entrypoint) : '[^.]+'
        arg.to_s.match?(/\A--entrypoints\.#{name}\.http\.aliasheadersstrategy/i)
      end

      # Every entrypoint the command declares, HELIOS-generated or imported.
      def entrypoints(command)
        command.filter_map { |arg| arg.to_s[/\A--entrypoints\.([^.]+)\./i, 1] }.uniq
      end

      def traefik_image
        configuration.reverse_proxy.image.presence || DockerImages.current(:TRAEFIK)
      end

      # Only when the pinned tag proves the version is new enough. A rolling tag
      # (`v3`, `latest`), a digest or an unparsable tag can still resolve to an
      # older binary on the host, and a Traefik that does not know the flag
      # refuses to start at all — so stay silent rather than break the stack.
      def alias_headers_supported?
        tag = traefik_image.split('/').last.to_s.split(':').last.to_s
        version = tag[/\Av?(\d+\.\d+(?:\.\d+)?)\z/, 1]
        return false unless version

        Gem::Version.new(version) >= ALIAS_HEADERS_MIN_VERSION
      end

      # Published ports, additively ensuring the HELIOS entrypoint port is bound
      # when routed through Traefik. Same additive/idempotent contract as
      # effective_traefik_command.
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
