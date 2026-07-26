module Import
  class ConfigurationImporter # rubocop:disable Metrics/ClassLength
    include Helpers

    # Sections whose data comes from a uniform `section_data` extractor call.
    # The remaining keys (sensors, senec, mqtt, shelly, devices, unmanaged)
    # need custom handling because of mode differences or non-extractor
    # sources, so they're merged in inside `full_result` / `collectors_only_result`.
    UNIFORM_FULL_EXTRACTORS = %i[
      deployment system dashboard postgresql influxdb redis watchtower ingest power_splitter
      forecast tibber senec_charger reverse_proxy backup helios
    ].freeze
    UNIFORM_COLLECTORS_ONLY_EXTRACTORS = %i[
      deployment system influxdb watchtower forecast tibber helios
    ].freeze

    def initialize(stack_reader)
      @reader = stack_reader
    end

    # Extracted data as plain hashes (no DB access). `partial_result` is the
    # full payload minus the unmanaged section; the unmanaged detector
    # depends on a dry-run that runs after the singletons are persisted, so
    # callers that don't need the unmanaged section should prefer
    # `partial_result` to avoid triggering detection too early.
    def result
      @result ||= partial_result.merge(unmanaged: unmanaged_detector.detect)
    end

    def partial_result
      @partial_result ||= collectors_only? ? collectors_only_partial_result : full_partial_result
    end

    # Persist extracted data into config.yaml
    def import!
      config = Configuration.current

      persist_singletons!(config)
      sensor_persister.persist!(config) unless collectors_only?
      mark_balcony_sensor!(config)
      # Snapshot which env keys HELIOS will canonically emit. Runs after the
      # singleton sections have been persisted (so Configuration is fully
      # populated) but before unmanaged detection consumes the snapshot.
      @emitted_canonical_keys = compute_emitted_canonical_keys(config)
      persist_unmanaged!(config)

      config
    end

    # Ingest-relevant sensors the import would store as `source: external`
    # while the stack runs an Ingest service. HELIOS routes every Ingest input
    # through the proxy and cannot reroute an external writer, so adopting the
    # stack would drop Ingest and lose the house_power correction (see
    # Configuration#ingest_required?). Non-empty → the import is refused
    # (StartsController) so the user decides whether Ingest is still needed.
    def ingest_conflict_sensors
      return [] if collectors_only?
      return [] unless @reader.services.key?('ingest')
      # No balcony → HELIOS wouldn't run Ingest anyway, so external is no conflict.
      # (balcony_detector, not the dry-run config, since the is_balcony flag is
      # only set later in #mark_balcony_sensor!.)
      return [] if balcony_detector.sensor_names.empty?

      dryrun_configuration.external_ingest_inputs
    end

    def collectors_only?
      return @collectors_only if defined?(@collectors_only)

      services = @reader.services
      has_local_target = services.key?('dashboard') || services.key?('influxdb')
      has_any_collector = StackReader::COLLECTOR_SERVICES.any? { |s| services.key?(s) }

      @collectors_only = !has_local_target && has_any_collector
    end

    # Dashboard + InfluxDB run locally, the InfluxDB is exposed for remote
    # writes, and no local device collectors (senec/mqtt/shelly) are present —
    # i.e. the collectors run elsewhere and push into this stack's InfluxDB.
    # forecast-collector and power-splitter are fine (they're not device
    # collectors). Mutually exclusive with collectors_only? (which has no local
    # target at all).
    def dashboard_only?
      return @dashboard_only if defined?(@dashboard_only)

      services = @reader.services
      has_dashboard = services.key?('dashboard')
      has_influxdb = services.key?('influxdb')
      has_device_collector = StackReader::DEVICE_COLLECTOR_SERVICES.any? { |s| services.key?(s) }

      @dashboard_only = has_dashboard && has_influxdb && influxdb_exposed? && !has_device_collector
    end

    # Resolved deployment mode (collectors_only and dashboard_only are mutually
    # exclusive; everything else is the implicit full default).
    def mode
      if collectors_only?
        ConfigSchema::MODE_COLLECTORS_ONLY
      elsif dashboard_only?
        ConfigSchema::MODE_DASHBOARD_ONLY
      else
        ConfigSchema::MODE_FULL
      end
    end

    private

    # True when the imported compose publishes the InfluxDB container port 8086
    # to the host (the defining trait of dashboard_only: remote collectors write
    # in across the LAN).
    def influxdb_exposed?
      Array(@reader.service('influxdb')&.dig('ports')).any? do |entry|
        case entry
        when Hash then entry['target'].to_i == 8086
        else entry.to_s.split(':').last == '8086'
        end
      end
    end

    # --- Extractors (lazy-initialized) ---

    def senec_extractor
      @senec_extractor ||= SenecExtractor.new(@reader)
    end

    def shelly_extractor
      @shelly_extractor ||= ShellyExtractor.new(@reader, sensors_data)
    end

    def mqtt_extractor
      @mqtt_extractor ||= MqttExtractor.new(@reader, sensors_data)
    end

    def forecast_extractor
      @forecast_extractor ||= ForecastExtractor.new(@reader)
    end

    def tibber_extractor
      @tibber_extractor ||= TibberExtractor.new(@reader)
    end

    def senec_charger_extractor
      @senec_charger_extractor ||= SenecChargerExtractor.new(@reader)
    end

    def watchtower_extractor
      @watchtower_extractor ||= WatchtowerExtractor.new(@reader)
    end

    def system_extractor
      @system_extractor ||= SystemExtractor.new(
        @reader,
        watchtower_interval: watchtower_extractor.interval,
        watchtower_schedule: watchtower_extractor.schedule,
      )
    end

    def deployment_extractor
      @deployment_extractor ||= DeploymentExtractor.new(mode:)
    end

    def dashboard_extractor
      @dashboard_extractor ||= DashboardExtractor.new(@reader)
    end

    def redis_extractor
      @redis_extractor ||= RedisExtractor.new(@reader, volume_resolver)
    end

    def postgresql_extractor
      @postgresql_extractor ||= PostgresqlExtractor.new(@reader, volume_resolver)
    end

    def influxdb_extractor
      @influxdb_extractor ||= InfluxdbExtractor.new(@reader, volume_resolver, collectors_only: collectors_only?)
    end

    def reverse_proxy_extractor
      @reverse_proxy_extractor ||= ReverseProxyExtractor.new(@reader, volume_resolver)
    end

    def service_overrides_extractor
      @service_overrides_extractor ||= ServiceOverridesExtractor.new(@reader)
    end

    def backup_extractor
      @backup_extractor ||= BackupExtractor.new(@reader)
    end

    def ingest_extractor
      @ingest_extractor ||= IngestExtractor.new(@reader, volume_resolver, balcony_detector)
    end

    def helios_extractor
      @helios_extractor ||= HeliosExtractor.new(@reader)
    end

    def power_splitter_extractor
      @power_splitter_extractor ||= PowerSplitterExtractor.new(@reader)
    end

    def sensors_extractor
      @sensors_extractor ||= SensorsExtractor.new(
        @reader,
        senec_measurement: senec_extractor.measurement,
        forecast_measurement: forecast_extractor.measurement,
      )
    end

    def unmanaged_detector
      @unmanaged_detector ||= UnmanagedDetector.new(
        @reader,
        known_measurements:,
        traefik_adopted: reverse_proxy_extractor.section_data.present?,
        emitted_canonical_keys: emitted_canonical_keys,
      )
    end

    # Dry-run Export::Env on the persisted Configuration so the unmanaged
    # detector can ask "will HELIOS canonically emit this var?" instead of
    # approximating via a hand-curated MANAGED_ENV_KEYS list. The latter
    # silently mis-skipped conditionally-emitted vars (SENEC_HOST in cloud
    # mode, SOLCAST_* without solcast forecast, etc.) and dropped values that
    # unmanaged services still needed at runtime.
    #
    # `import!` overrides @emitted_canonical_keys early with the persisted
    # Configuration. Tests that hit `result` directly fall through to a
    # dry-run on a Configuration assembled from the in-memory partial result.
    def emitted_canonical_keys
      @emitted_canonical_keys ||= compute_emitted_canonical_keys(dryrun_configuration)
    end

    def compute_emitted_canonical_keys(config)
      env_file = ::Env::File.new(File::NULL)
      Export::Env::SECTIONS.each do |klass, enabled|
        next if klass == Export::Env::Unmanaged
        next unless enabled.call(config)

        klass.new(env_file, config).call
      end
      env_file.keys.to_set
    end

    # Build a Configuration from the in-memory partial result, running the
    # SensorPersister so sensors are stored as the hash-of-hashes shape that
    # Configuration's accessors expect — extractor output is a flat
    # name → measurement string map and would crash Data.wrap.
    def dryrun_configuration
      config = Configuration.from_data(partial_result.except(:sensors))
      sensor_persister.persist!(config) unless collectors_only?
      config
    end

    def volume_resolver
      @volume_resolver ||= VolumeResolver.new(@reader)
    end

    def balcony_detector
      @balcony_detector ||= BalconyDetector.new(@reader, sensors_data)
    end

    def sensors_data
      sensors_extractor.sensors_data
    end

    def known_measurements
      from_sensors = sensors_data.values.filter_map { |v| v.to_s.split(':', 2).first.presence }
      from_mqtt = mqtt_extractor.enabled? ? mqtt_extractor.mappings.filter_map { |m| m[:measurement].presence } : []
      (from_sensors + from_mqtt).uniq
    end

    def sensor_persister
      @sensor_persister ||= SensorPersister.new(
        sensors_data:,
        devices: partial_result[:devices],
        enabled_collectors: enabled_collectors,
        mqtt_mappings: mqtt_extractor.enabled? ? mqtt_extractor.mappings : [],
        excluded_sensors: sensors_extractor.excluded_sensor_names,
        senec_measurement: senec_extractor.measurement,
      )
    end

    def enabled_collectors
      [
        (:senec if senec_extractor.enabled?),
        (:forecast if forecast_extractor.enabled?),
      ].compact
    end

    # --- Result building ---

    def full_partial_result
      @full_partial_result ||= uniform_sections(UNIFORM_FULL_EXTRACTORS).merge(
        sensors: sensors_data,
        senec: senec_extractor.section_data,
        mqtt: mqtt_section_data,
        shelly: shelly_section_data,
        devices: build_devices,
        service_overrides: service_overrides_extractor.section_data,
      )
    end

    # Sensor canonicalization lives on the remote dashboard host, so HELIOS
    # cannot reliably map collector env vars back to canonical sensor names.
    # Collector connection data (hosts, credentials) is extracted into the
    # usual senec/shelly/mqtt sections; the opaque mapping payload is kept
    # as a raw list in mqtt.mappings and shelly.devices.
    def collectors_only_partial_result
      @collectors_only_partial_result ||= uniform_sections(UNIFORM_COLLECTORS_ONLY_EXTRACTORS).merge(
        senec: collectors_only_senec_data,
        mqtt: collectors_only_mqtt_data,
        shelly: collectors_only_shelly_data,
        service_overrides: service_overrides_extractor.section_data,
      )
    end

    def uniform_sections(keys)
      keys.index_with { |key| send("#{key}_extractor").section_data }
    end

    def collectors_only_senec_data
      data = senec_extractor.section_data
      return nil unless data

      data.merge('image' => senec_extractor.image).compact
    end

    def collectors_only_mqtt_data
      broker = mqtt_extractor.broker_data
      mappings = mqtt_extractor.raw_mappings
      data = (broker || {}).merge(image_data_for('mqtt-collector'),
                                  'mappings' => mappings.presence).compact
      data.presence
    end

    # Full-mode mqtt section: broker plus orphan mappings (preserved so the
    # InfluxDB time series stays gap-free across re-export).
    def mqtt_section_data
      broker = mqtt_extractor.broker_data
      orphans = mqtt_extractor.orphan_mappings
      data = (broker || {}).merge('mappings' => orphans.presence).compact
      data.presence
    end

    def collectors_only_shelly_data
      shelly_section_data(include_image: true)
    end

    # Shelly section: connection/interval plus, only for standalone devices,
    # the per-device list. A device that feeds a `source: shelly` sensor lives
    # on that sensor (with its own device_id/host) via SensorPersister, so it
    # appears exactly once in config.yaml. shelly.devices therefore holds only
    # devices no sensor consumes — see #standalone_shelly_devices.
    def shelly_section_data(include_image: false)
      section = shelly_extractor.section_data
      return nil unless section

      extras = {
        'password' => shelly_extractor.shared_password,
        'devices' => standalone_shelly_devices.presence,
      }
      # Only collectors-only stacks pin the donor image; full mode manages the
      # collector image centrally (same as senec/mqtt), so it stays unset and
      # the export falls back to the HELIOS baseline.
      extras.merge!(image_data_for('shelly-collector')) if include_image
      section.merge(extras).compact.presence
    end

    # Shelly devices that no imported sensor consumes. In collectors_only mode
    # HELIOS imports no logical sensors (canonicalization happens on the remote
    # dashboard host), so the full device list survives here as the round-trip
    # source of truth. In full mode a device feeding a `source: shelly` sensor
    # is represented on that sensor instead, leaving only true standalone
    # devices in shelly.devices.
    def standalone_shelly_devices
      devices = shelly_extractor.raw_devices
      return devices if collectors_only?

      devices.reject { |device| shelly_sensor_claims_measurement?(device['measurement']) }
    end

    # True when a `source: shelly` sensor will claim this measurement — i.e. a
    # sensor maps it to a Shelly power field. That mirrors the importer's source
    # inference (SensorPersister#shelly_device_provides_sensor?): exactly those
    # devices get folded onto their sensor, so they must not also linger in
    # shelly.devices. A measurement consumed only by a non-power (external/mqtt)
    # sensor — or by no sensor at all — stays a standalone device.
    def shelly_sensor_claims_measurement?(measurement)
      return false if measurement.blank?

      claims = SHELLY_POWER_FIELDS.map { |field| "#{measurement}:#{field}" }
      sensors_data.values.any? { |mapping| claims.include?(mapping.to_s) }
    end

    def build_devices
      devices = []
      devices << senec_extractor.device_data if senec_extractor.enabled?
      devices.concat(shelly_extractor.device_data) if shelly_extractor.enabled?
      devices.concat(mqtt_extractor.device_data) if mqtt_extractor.enabled?
      devices
    end

    # --- Persistence ---

    def persist_singletons!(config)
      %i[deployment system dashboard postgresql influxdb redis watchtower ingest power_splitter sensors
         forecast senec mqtt tibber senec_charger shelly reverse_proxy backup helios
         service_overrides].each do |key|
        config.update(key.to_s, partial_result[key]) if partial_result[key]
      end
    end

    def persist_unmanaged!(config)
      unmanaged = result[:unmanaged]
      config.update_unmanaged(unmanaged) if unmanaged.present?
    end

    def mark_balcony_sensor!(config)
      balcony_detector.sensor_names.each do |name|
        existing = config.sensor_config(name).to_h
        config.update_sensor(name, existing.merge('is_balcony' => true))
      end
    end
  end
end
