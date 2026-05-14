module Import
  class ConfigurationImporter # rubocop:disable Metrics/ClassLength
    include Helpers

    # Sections whose data comes from a uniform `section_data` extractor call.
    # The remaining keys (sensors, senec, mqtt, shelly, devices, unmanaged)
    # need custom handling because of mode differences or non-extractor
    # sources, so they're merged in inside `full_result` / `collectors_only_result`.
    UNIFORM_FULL_EXTRACTORS = %i[
      deployment system dashboard postgresql influxdb redis watchtower ingest power_splitter
      forecast reverse_proxy backup
    ].freeze
    UNIFORM_COLLECTORS_ONLY_EXTRACTORS = %i[
      deployment system influxdb watchtower forecast
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

    def collectors_only?
      return @collectors_only if defined?(@collectors_only)

      services = @reader.services
      has_local_target = services.key?('dashboard') || services.key?('influxdb')
      has_any_collector = StackReader::COLLECTOR_SERVICES.any? { |s| services.key?(s) }

      @collectors_only = !has_local_target && has_any_collector
    end

    private

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

    def watchtower_extractor
      @watchtower_extractor ||= WatchtowerExtractor.new(@reader)
    end

    def system_extractor
      @system_extractor ||= SystemExtractor.new(
        @reader,
        watchtower_interval: watchtower_extractor.interval,
      )
    end

    def deployment_extractor
      @deployment_extractor ||= DeploymentExtractor.new(collectors_only: collectors_only?)
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

    def power_splitter_extractor
      @power_splitter_extractor ||= PowerSplitterExtractor.new(@reader)
    end

    def sensors_extractor
      @sensors_extractor ||= SensorsExtractor.new(@reader)
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
        shelly_multi_device: shelly_extractor.multi_device?,
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

    # Full-mode shelly section: connection/interval plus the per-device list
    # for multi-device stacks (CSV-valued single service, or several
    # shelly-collector-<suffix> services). Single-instance, single-device
    # setups continue to ride through the per-sensor shelly_host pathway in
    # SensorPersister — devices: stays nil there to avoid duplicating
    # information that already lives on each `source: shelly` sensor.
    def shelly_section_data(include_image: false)
      section = shelly_extractor.section_data
      return nil unless section

      devices = shelly_extractor.multi_device? ? shelly_extractor.raw_devices : nil
      extras = {
        'password' => shelly_extractor.shared_password,
        'devices' => devices&.presence,
      }
      extras.merge!(image_data_for('shelly-collector')) if include_image || devices
      section.merge(extras).compact.presence
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
         forecast senec mqtt shelly reverse_proxy backup service_overrides].each do |key|
        config.update(key.to_s, partial_result[key]) if partial_result[key]
      end
    end

    def persist_unmanaged!(config)
      unmanaged = result[:unmanaged]
      config.update_unmanaged(unmanaged) if unmanaged.present?
    end

    def mark_balcony_sensor!(config)
      name = balcony_detector.sensor_name
      return unless name

      existing = config.sensor_config(name).to_h
      config.update_sensor(name, existing.merge('is_balcony' => true))
    end
  end
end
