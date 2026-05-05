module Import
  class ConfigurationImporter
    include Helpers

    # Sections whose data comes from a uniform `section_data` extractor call.
    # The remaining keys (sensors, senec, mqtt, shelly, devices, unmanaged)
    # need custom handling because of mode differences or non-extractor
    # sources, so they're merged in inside `full_result` / `collectors_only_result`.
    UNIFORM_FULL_EXTRACTORS = %i[
      system dashboard postgresql influxdb redis watchtower ingest
      forecast reverse_proxy backup
    ].freeze
    UNIFORM_COLLECTORS_ONLY_EXTRACTORS = %i[
      system influxdb watchtower forecast
    ].freeze

    def initialize(stack_reader)
      @reader = stack_reader
    end

    # Extracted data as plain hashes (no DB access)
    def result
      @result ||= build_result
    end

    # Persist extracted data into config.yaml
    def import!
      config = Configuration.current

      persist_singletons!(config)
      sensor_persister.persist!(config) unless collectors_only?
      mark_balcony_sensor!(config)
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
        collectors_only: collectors_only?,
        watchtower_interval: watchtower_extractor.interval,
      )
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

    def sensors_extractor
      @sensors_extractor ||= SensorsExtractor.new(@reader)
    end

    def unmanaged_detector
      @unmanaged_detector ||= UnmanagedDetector.new(
        @reader,
        known_measurements:,
        traefik_adopted: reverse_proxy_extractor.section_data.present?,
      )
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
        devices: result[:devices],
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

    def build_result
      collectors_only? ? collectors_only_result : full_result
    end

    def full_result
      uniform_sections(UNIFORM_FULL_EXTRACTORS).merge(
        sensors: sensors_data,
        senec: senec_extractor.section_data,
        mqtt: mqtt_section_data,
        shelly: shelly_extractor.section_data,
        devices: build_devices,
        service_overrides: service_overrides_extractor.section_data,
        unmanaged: unmanaged_detector.detect,
      )
    end

    # Sensor canonicalization lives on the remote dashboard host, so HELIOS
    # cannot reliably map collector env vars back to canonical sensor names.
    # Collector connection data (hosts, credentials) is extracted into the
    # usual senec/shelly/mqtt sections; the opaque mapping payload is kept
    # as a raw list in mqtt.mappings and shelly.devices.
    def collectors_only_result
      uniform_sections(UNIFORM_COLLECTORS_ONLY_EXTRACTORS).merge(
        senec: collectors_only_senec_data,
        mqtt: collectors_only_mqtt_data,
        shelly: collectors_only_shelly_data,
        service_overrides: service_overrides_extractor.section_data,
        unmanaged: unmanaged_detector.detect,
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
      section = shelly_extractor.section_data
      devices = shelly_extractor.raw_devices
      data = (section || {}).merge(image_data_for('shelly-collector'),
                                   'mode' => shelly_extractor.influx_mode,
                                   'password' => shelly_extractor.shared_password,
                                   'devices' => devices.presence).compact
      data.presence
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
      %i[system dashboard postgresql influxdb redis watchtower ingest sensors forecast senec mqtt
         shelly reverse_proxy backup service_overrides].each do |key|
        config.update(key.to_s, result[key]) if result[key]
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
