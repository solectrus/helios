module Export
  module Services
    class Influxdb < Base
      # Container port the InfluxDB HTTP API/UI always listens on.
      CONTAINER_PORT = 8086

      # Max open files for the InfluxDB container. Each shard keeps several
      # index/TSM files open, so a long history (hundreds of shards) blows
      # past Docker's default soft limit (often 1024) with "too many open
      # files" on shard open. 65536 is InfluxData's recommended minimum.
      NOFILE_LIMIT = 65_536

      def self.service_name
        'influxdb'
      end

      def self.config_keys
        ['influxdb']
      end

      def self.volume_env_key
        'INFLUX_VOLUME_PATH'
      end

      def self.proxy_subdomain
        'influxdb'
      end

      # An InfluxDB kept inside the stack gets no route: the external proxy
      # answers the internet, and a router for it would open a database the
      # user chose not to open.
      def self.externally_routable?(configuration)
        enabled?(configuration) && exposed?(configuration)
      end

      def self.comment
        'InfluxDB — Time-series database for sensor measurements'
      end

      def self.enabled?(configuration)
        !configuration.collectors_only?
      end

      # True when InfluxDB should be reachable from outside the Docker
      # network. In dashboard_only mode the collectors run on a remote host
      # and write into this stack's InfluxDB across the LAN, so it has to be
      # exposed regardless of the user's preference.
      def self.exposed?(configuration)
        configuration.dashboard_only? || configuration.influxdb.publish_port.present?
      end

      # Host-side port InfluxDB is reachable on — either published directly
      # or served by Traefik's `influxdb` entrypoint.
      def self.host_port(configuration)
        configuration.influxdb.host_port.presence || CONTAINER_PORT
      end

      # True when a managed Traefik routes InfluxDB, which it does whenever
      # one runs and InfluxDB is exposed at all: HELIOS owns the routers of
      # its own services and the entrypoints they name
      # (see Export::Services::Traefik::OWNED_ENTRYPOINTS).
      def self.traefik_managed_routing?(configuration)
        exposed?(configuration) && Traefik.enabled?(configuration)
      end

      def data_directories
        # The staging directory is a plain bind mount (see #influxdb_volumes),
        # not a managed volume, so it must be listed here explicitly. Without
        # it, Export::Builder never creates the source directory and InfluxDB
        # fails to start on daemons that refuse missing bind-mount sources
        # (e.g. Synology DSM with Docker 24.0.2).
        managed_data_directory + [DetachedRunner::INFLUX_STAGING_DIRNAME]
      end

      def to_h
        config = {
          image: configuration.influxdb.image,
          environment: influxdb_environment,
          volumes: influxdb_volumes,
          ulimits: influxdb_ulimits,
          restart: 'unless-stopped',
          stop_grace_period: STOP_GRACE_PERIOD,
          healthcheck: healthcheck('CMD', 'influx', 'ping'),
        }

        config.merge(routing)
      end

      private

      # How InfluxDB is reached from outside, if at all.
      #
      # The managed Traefik routes it by label (HTTPS, same domain). An
      # external proxy on the shared network reaches it by name, and the
      # exposure toggle still decides whether it is routed at all: that proxy
      # answers the internet, and an InfluxDB kept inside the stack must not
      # get a route. Otherwise the host port is published directly.
      def routing
        return { labels: traefik_router_labels(entrypoint: 'influxdb', port: CONTAINER_PORT) } if
          traefik_managed_routing?
        return { labels: exposed? ? shared_network_router_labels(port: CONTAINER_PORT) : nil } if
          shared_network_routing?
        return { ports: ["#{host_port}:#{CONTAINER_PORT}"] } if exposed?

        {}
      end

      def exposed?
        self.class.exposed?(configuration)
      end

      def host_port
        self.class.host_port(configuration)
      end

      def traefik_managed_routing?
        self.class.traefik_managed_routing?(configuration)
      end

      # The second mount is the shared influx-backup staging directory.
      # `influx backup` writes its (already-gzipped) output there, and the
      # backup/restore sidecars see the same path under the same name —
      # avoids a docker-exec stdio pipe for multi-GB dumps and a wasted
      # gzip-on-gzip pass. `./` resolves against the compose project
      # directory (HELIOS's data path).
      def influxdb_volumes
        [
          bind_mount('/var/lib/influxdb2'),
          "./#{DetachedRunner::INFLUX_STAGING_DIRNAME}:#{DetachedRunner::INFLUX_STAGING_MOUNT}",
        ]
      end

      def influxdb_ulimits
        { nofile: { soft: NOFILE_LIMIT, hard: NOFILE_LIMIT } }
      end

      def influxdb_environment
        env = [
          'TZ',
          'DOCKER_INFLUXDB_INIT_MODE=setup',
          'DOCKER_INFLUXDB_INIT_USERNAME=admin',
          'DOCKER_INFLUXDB_INIT_PASSWORD=${INFLUX_PASSWORD}',
          'DOCKER_INFLUXDB_INIT_ORG=${INFLUX_ORG}',
          'DOCKER_INFLUXDB_INIT_BUCKET=${INFLUX_BUCKET}',
          'DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=${INFLUX_ADMIN_TOKEN}',
        ]
        env << 'INFLUXD_USE_HASHED_TOKENS' if configuration.influxdb.use_hashed_tokens.present?
        env
      end
    end
  end
end
