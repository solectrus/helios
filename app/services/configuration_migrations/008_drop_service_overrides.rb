module ConfigurationMigrations
  # Drops the section that carried Traefik labels an import rescued.
  #
  # HELIOS writes the routers of its own services itself, so a rescued router
  # named the same thing twice and a rescued middleware hung on a router the
  # import had already taken apart. Nothing read the section any more, and a
  # section nothing reads invites a change that does nothing.
  #
  # An installation whose labels HELIOS cannot write again is refused at the
  # import instead (see Import::CompatibilityCheck#unsupported_routing), so
  # nothing arrives here that the export cannot produce.
  #
  # One rescued router said something the configuration holds nowhere else: a
  # router on the InfluxDB service made the database reachable from outside.
  # HELIOS reads that from `influxdb.publish_port` now, and an installation
  # adopted before that field existed carries the answer in the labels alone.
  # Dropped without a word, the database would lose its route, the entrypoint
  # that router named and the port that entrypoint published. So the answer is
  # read out of the section first, the same way the import reads it off a
  # running stack (see Import::ConfigurationImporter::InfluxdbExtractor).
  class DropServiceOverrides < Base
    version 8

    # Container port the InfluxDB HTTP API always listens on. A host port that
    # matches it is the default and is therefore not stored.
    INFLUXDB_CONTAINER_PORT = '8086'.freeze

    ROUTER_LABEL = /\Atraefik\.http\.routers\./i

    # The `influxdb` entrypoint of the adopted Traefik, which carries the port
    # the database answered on.
    ENTRYPOINT_ADDRESS = /\A--entrypoints\.influxdb\.address=\S*?:(\d+)\z/i

    def up(data)
      overrides = data.delete('service_overrides')
      adopt_influxdb_route(data) if routed_influxdb?(overrides)

      data
    end

    private

    def routed_influxdb?(overrides)
      return false unless overrides.is_a?(Hash)

      labels = overrides['influxdb'].is_a?(Hash) ? overrides['influxdb']['labels'] : nil
      Array(labels).any? { |label| label.to_s.match?(ROUTER_LABEL) }
    end

    # `publish_port` alone makes the export route the database again. The port
    # follows only where it is not the canonical one, which is how the field is
    # stored everywhere else.
    def adopt_influxdb_route(data)
      influxdb = data['influxdb']
      influxdb = data['influxdb'] = {} unless influxdb.is_a?(Hash)

      influxdb['publish_port'] = true unless influxdb.key?('publish_port')

      port = entrypoint_port(data)
      influxdb['host_port'] = port if port && !influxdb.key?('host_port')
    end

    def entrypoint_port(data)
      reverse_proxy = data['reverse_proxy']
      return unless reverse_proxy.is_a?(Hash)

      port = Array(reverse_proxy['command']).filter_map { |arg| arg.to_s[ENTRYPOINT_ADDRESS, 1] }.first

      port if port && port != INFLUXDB_CONTAINER_PORT
    end
  end
end
