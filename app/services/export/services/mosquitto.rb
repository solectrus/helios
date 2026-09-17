module Export
  module Services
    # MQTT broker HELIOS runs for the stack, so devices (a wallbox, a heat
    # pump, a smart plug) can publish without a broker of their own.
    #
    # Mosquitto 2.x listens on localhost alone until a configuration file
    # names a listener, and it has no command-line flags for listeners or
    # authentication. HELIOS writes only compose.yaml and .env (ADR-0003), so
    # the container builds its own configuration at start: the `command`
    # writes the file (plus a password file, if credentials are set) and then
    # replaces itself with the broker.
    #
    # A broker HELIOS runs always demands a login. The MQTT survey asks for
    # both halves and takes neither as optional, and the generated
    # configuration says `allow_anonymous false` whatever it finds, so a
    # broker that takes messages from anyone can never come out of it.
    class Mosquitto < Base
      # Port inside the compose network. Only the published host port is
      # configurable, because that one can already be taken on the host.
      CONTAINER_PORT = 1883

      # Host port of the TLS entrypoint Traefik serves the broker on. The
      # plain port stays configurable (the host can already run a broker on
      # 1883), 8883 is the registered MQTTS port and needs no knob of its own.
      TLS_HOST_PORT = 8883

      CONFIG_FILE = '/mosquitto/config/helios.conf'.freeze
      PASSWORD_FILE = '/mosquitto/config/helios.passwd'.freeze
      DATA_DIRECTORY = '/mosquitto/data'.freeze

      # The broker logs every connection, and a client that subscribes just to
      # prove the broker answers would bury the connections of the real devices
      # under its own. So the check reads the listening socket instead, which
      # says the same thing without touching it: the broker refuses to start
      # at all when its configuration or its password file is unusable.
      HEALTHCHECK_COMMAND = "netstat -ltn | grep -q ':#{CONTAINER_PORT} '".freeze

      # UID/GID of the image's `mosquitto` user. The entrypoint runs as root
      # and the broker drops to that user itself, so a password file written
      # by the command stays unreadable (`Unable to open pwfile`) unless it
      # changes hands first.
      RUN_AS = '1883:1883'.freeze

      def self.service_name
        'mosquitto'
      end

      def self.config_keys
        ['mosquitto']
      end

      def self.volume_env_key
        'MOSQUITTO_VOLUME_PATH'
      end

      def self.comment
        'Mosquitto — MQTT broker for devices that publish measurements'
      end

      # The broker stands on its own: it runs as soon as the user hands it to
      # HELIOS, even where no sensor and no topic reads from it yet. The
      # collector has its own gate and can stay down while devices already
      # publish. A dashboard-only stack runs no collectors at all, so it runs
      # no broker either.
      def self.enabled?(configuration)
        return false if configuration.dashboard_only?

        configuration.mqtt_broker_managed?
      end

      # The broker speaks MQTT on its port, not HTTP, so a browser has
      # nothing to open there.
      def self.browsable?
        false
      end

      # No broker is adopted, not even one HELIOS wrote itself. HELIOS
      # generates the whole broker configuration on every export, so it would
      # overwrite a broker the user brought along, and keeping one verbatim
      # would leave two brokers in the stack as soon as HELIOS runs its own.
      # The import refuses every trace of one, and the UI stays the single way
      # to get a broker. Switching it on there takes one answer in the MQTT
      # survey.
      def self.adoptable?
        false
      end

      # Host-side port the broker answers plain MQTT on, published directly
      # or served by Traefik's `mqtt` entrypoint.
      def self.host_port(configuration)
        configuration.mosquitto.port.presence || CONTAINER_PORT
      end

      # True when a managed Traefik routes the broker, which it does whenever
      # one runs and the broker runs with it: HELIOS owns the routers of its
      # own services and the entrypoints they name
      # (see Export::Services::Traefik::OWNED_ENTRYPOINTS).
      def self.traefik_managed_routing?(configuration)
        enabled?(configuration) && Traefik.enabled?(configuration)
      end

      # Whether the broker can write a password file. Single source of truth:
      # the collector emits the matching credential vars and
      # Export::Env::Mosquitto writes them, so all three must read the same
      # rule.
      #
      # Both halves must be there. `mosquitto_passwd -b` refuses an empty
      # user name, `sh -e` then stops, and the broker never starts, which
      # holds the collector down as well (depends_on: service_healthy).
      def self.authenticated?(configuration)
        mosquitto = configuration.mosquitto

        mosquitto.password.present? && mosquitto.username.present?
      end

      def data_directories
        managed_data_directory
      end

      def to_h
        config = {
          image: configuration.mosquitto.image.presence || DockerImages.current(:MOSQUITTO),
          command: ['sh', '-ec', startup_command],
          environment: environment,
          volumes: [bind_mount(DATA_DIRECTORY)],
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD-SHELL', HEALTHCHECK_COMMAND),
        }

        if traefik_managed_routing?
          # HELIOS owns Traefik: it publishes the two broker ports and routes
          # them here, so a port of its own would only clash with them.
          config[:labels] = traefik_labels
        else
          config[:ports] = ["#{host_port}:#{CONTAINER_PORT}"]
        end

        config
      end

      private

      # Two TCP routers on one service. MQTT is not HTTP, so Traefik cannot
      # read a host name out of the stream: a router without TLS matches
      # every connection on its entrypoint (`HostSNI(*)`), and only a router
      # that terminates TLS reads the name from the SNI of the handshake.
      # Hence one entrypoint each, rather than one that serves both.
      #
      # The plain router stays for devices that speak no TLS. The TLS one
      # carries a Let's Encrypt certificate and hands the stream to the same
      # broker, which sees plain MQTT either way.
      def traefik_labels
        domain = configuration.public_host
        [
          'traefik.enable=true',
          'traefik.tcp.routers.mqtt.rule=HostSNI(`*`)',
          'traefik.tcp.routers.mqtt.entrypoints=mqtt',
          'traefik.tcp.routers.mqtt.service=mqtt',
          "traefik.tcp.routers.mqtts.rule=HostSNI(`#{domain}`)",
          'traefik.tcp.routers.mqtts.entrypoints=mqtts',
          "traefik.tcp.routers.mqtts.tls.certresolver=#{Traefik.certresolver(configuration)}",
          'traefik.tcp.routers.mqtts.service=mqtt',
          "traefik.tcp.services.mqtt.loadbalancer.server.port=#{CONTAINER_PORT}",
        ]
      end

      def authenticated?
        self.class.authenticated?(configuration)
      end

      def environment
        ['TZ', *(%w[MQTT_USERNAME MQTT_PASSWORD] if authenticated?)]
      end

      # The script that replaces the image's own command. `sh -e` stops at the
      # first failing line, so the broker never starts on a half-written
      # configuration. `$$` is what compose leaves as a single `$` for the
      # shell, so the credentials stay in .env.
      def startup_command
        [*password_file_script, config_file_script, "exec mosquitto -c #{CONFIG_FILE}"].join("\n")
      end

      # `mosquitto_passwd -c` refuses to overwrite an existing file, and a
      # restarted container still carries the one from its last start, so the
      # file goes first.
      def password_file_script
        return [] unless authenticated?

        [
          "rm -f #{PASSWORD_FILE}",
          %(mosquitto_passwd -b -c #{PASSWORD_FILE} "$$MQTT_USERNAME" "$$MQTT_PASSWORD"),
          "chown #{RUN_AS} #{PASSWORD_FILE}",
        ]
      end

      def config_file_script
        <<~SH.chomp
          cat > #{CONFIG_FILE} <<'CONF'
          #{config_lines.join("\n")}
          CONF
        SH
      end

      # Retained messages are the whole point for devices that publish rarely,
      # so the in-memory database goes to the bind mount.
      #
      # `allow_anonymous false` stands whatever the configuration holds. Where
      # a credential is missing, HELIOS cannot write the password file, and
      # the broker starts and turns every client away. That is the safe end of
      # a configuration HELIOS cannot carry out: the stack stays up, and the
      # broker never falls back to taking messages from anyone.
      def config_lines
        [
          "listener #{CONTAINER_PORT}",
          'allow_anonymous false',
          *("password_file #{PASSWORD_FILE}" if authenticated?),
          'persistence true',
          "persistence_location #{DATA_DIRECTORY}/",
        ]
      end
    end
  end
end
