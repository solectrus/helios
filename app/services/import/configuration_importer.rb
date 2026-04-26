module Import
  class ConfigurationImporter # rubocop:disable Metrics/ClassLength
    include Helpers

    # Env var that carries the absolute host path for each service's data dir
    # in legacy SOLECTRUS installs, plus the relative bind mount HELIOS defaults
    # to — used to decide if a preserved path is equivalent to the default.
    # Keyed by config section; default_dir usually equals the section name
    # except for reverse_proxy, which hosts the traefik container.
    VOLUME_PATH_ENVS = {
      'postgresql' => { env_key: 'DB_VOLUME_PATH', default_dir: 'postgresql' },
      'influxdb' => { env_key: 'INFLUX_VOLUME_PATH', default_dir: 'influxdb' },
      'redis' => { env_key: 'REDIS_VOLUME_PATH', default_dir: 'redis' },
      'ingest' => { env_key: 'INGEST_VOLUME_PATH', default_dir: 'ingest' },
      'reverse_proxy' => { env_key: 'TRAEFIK_VOLUME_PATH', default_dir: 'traefik' },
    }.freeze

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

    def unmanaged_detector
      @unmanaged_detector ||= UnmanagedDetector.new(@reader, known_measurements:)
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
        excluded_sensors: excluded_sensor_names,
      )
    end

    def enabled_collectors
      [
        (:senec if senec_extractor.enabled?),
        (:forecast if forecast_extractor.enabled?),
      ].compact
    end

    # The imported stack has an ingest service and at least one individual
    # inverter sensor we can flag as balcony power plant. The highest-numbered
    # sensor wins — main roof inverters are typically the lowest slot;
    # balcony generators get added later.
    def balcony_sensor_name
      return @balcony_sensor_name if defined?(@balcony_sensor_name)

      @balcony_sensor_name =
        if @reader.services.key?('ingest')
          SensorRegistry::BALCONY_CAPABLE_SENSORS.rfind { |name| sensors_data.key?(name) }
        end
    end

    # --- Result building ---

    def build_result
      collectors_only? ? collectors_only_result : full_result
    end

    def full_result # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
      {
        system: system_data,
        dashboard: dashboard_data,
        postgresql: postgresql_data,
        influxdb: influxdb_data,
        redis: redis_data,
        watchtower: watchtower_data,
        ingest: ingest_section_data,
        sensors: sensors_data,
        forecast: forecast_extractor.section_data,
        senec: senec_extractor.section_data,
        mqtt: mqtt_extractor.broker_data,
        shelly: shelly_extractor.section_data,
        reverse_proxy: reverse_proxy_data,
        backup: backup_data,
        devices: build_devices,
        unmanaged: unmanaged_detector.detect,
      }
    end

    # Sensor canonicalization lives on the remote dashboard host, so HELIOS
    # cannot reliably map collector env vars back to canonical sensor names.
    # Collector connection data (hosts, credentials) is extracted into the
    # usual senec/shelly/mqtt sections; the opaque mapping payload is kept
    # as a raw list in mqtt.mappings and shelly.devices.
    def collectors_only_result
      {
        system: system_data,
        influxdb: influxdb_data,
        watchtower: watchtower_data,
        forecast: forecast_extractor.section_data,
        senec: collectors_only_senec_data,
        mqtt: collectors_only_mqtt_data,
        shelly: collectors_only_shelly_data,
        unmanaged: unmanaged_detector.detect,
      }
    end

    def collectors_only_senec_data
      data = senec_extractor.section_data
      return nil unless data

      data.merge('image' => senec_extractor.image).compact
    end

    def collectors_only_mqtt_data
      broker = mqtt_extractor.broker_data
      mappings = mqtt_extractor.raw_mappings
      image = Compose.normalize_image(@reader.service('mqtt-collector')&.dig('image'))
      data = (broker || {}).merge('image' => image, 'mappings' => mappings.presence).compact
      data.presence
    end

    def collectors_only_shelly_data
      section = shelly_extractor.section_data
      devices = shelly_extractor.raw_devices
      image = Compose.normalize_image(@reader.service('shelly-collector')&.dig('image'))
      data = (section || {}).merge('image' => image, 'mode' => shelly_extractor.influx_mode,
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
         shelly reverse_proxy backup].each do |key|
        config.update(key.to_s, result[key]) if result[key]
      end
    end

    def persist_unmanaged!(config)
      unmanaged = result[:unmanaged]
      config.update_unmanaged(unmanaged) if unmanaged.present?
    end

    def mark_balcony_sensor!(config)
      return unless balcony_sensor_name

      existing = config.sensor_config(balcony_sensor_name).to_h
      config.update_sensor(balcony_sensor_name, existing.merge('is_balcony' => true))
    end

    # --- System ---

    def system_data
      data = system_core_data.merge(system_dashboard_data)
      data['mode'] = ConfigSchema::MODE_COLLECTORS_ONLY if collectors_only?
      data.compact
    end

    def system_core_data
      dashboard_env = service_env('dashboard')

      # Legacy compose files often define TZ in .env but don't reference it
      # from the dashboard service — fall back to raw_env so the user's
      # timezone survives the round-trip.
      {
        'timezone' => dashboard_env['TZ'].presence || @reader.raw_env['TZ'].presence,
        'installation_date' => dashboard_env['INSTALLATION_DATE'],
        'admin_password' => @reader.raw_env['ADMIN_PASSWORD'],
        'secret_key_base' => @reader.raw_env['SECRET_KEY_BASE'],
        'network_name' => imported_network_name,
        'update_interval' => watchtower_interval,
      }
    end

    # Picks up an explicit `networks: default: name:` override from the
    # imported compose. Without an override, leave it nil so HELIOS falls
    # back to its default — Docker would have auto-named the network the
    # same way for the imported stack.
    def imported_network_name
      name = @reader.raw_compose.dig('networks', 'default', 'name')
      name.presence
    end

    # --- Dashboard ---

    def dashboard_data
      image_data_for('dashboard')
    end

    def system_dashboard_data
      dashboard_env = service_env('dashboard')

      {
        'app_host' => dashboard_env['APP_HOST'],
        'co2_emission_factor' => dashboard_env['CO2_EMISSION_FACTOR'],
        'frame_ancestors' => dashboard_env['FRAME_ANCESTORS'],
        'ui_theme' => dashboard_env['UI_THEME'],
        'lockup_codeword' => dashboard_env['LOCKUP_CODEWORD'],
      }
    end

    # --- Infrastructure services ---

    def redis_data
      image_data_for('redis').merge(volume_path_data('redis')).compact
    end

    def watchtower_data
      image_data_for('watchtower')
    end

    # WATCHTOWER_POLL_INTERVAL takes precedence; some installations configure
    # the interval as a `--interval N` argument on the watchtower service
    # command instead, which is equally valid for Watchtower itself.
    def watchtower_interval
      env_value = @reader.raw_env['WATCHTOWER_POLL_INTERVAL'].presence
      return env_value if env_value

      command = @reader.service('watchtower')&.dig('command')
      tokens = Array(command).flat_map { |part| part.to_s.split }
      index = tokens.index('--interval')
      tokens[index + 1] if index && tokens[index + 1]
    end

    def postgresql_data
      {
        'image' => Compose.normalize_image(@reader.service('postgresql')&.dig('image')),
        'password' => @reader.raw_env['POSTGRES_PASSWORD'],
      }.merge(volume_path_data('postgresql')).compact
    end

    def influxdb_data
      collectors_only? ? external_influxdb_data : local_influxdb_data
    end

    def local_influxdb_data
      {
        'image' => Compose.normalize_image(@reader.service('influxdb')&.dig('image')),
        'password' => @reader.raw_env['INFLUX_PASSWORD'],
        'org' => @reader.raw_env['INFLUX_ORG'],
        'bucket' => @reader.raw_env['INFLUX_BUCKET'],
        'token' => influxdb_token,
      }.merge(volume_path_data('influxdb')).compact
    end

    def external_influxdb_data
      {
        'host' => @reader.raw_env['INFLUX_HOST'],
        'port' => @reader.raw_env['INFLUX_PORT'],
        'schema' => @reader.raw_env['INFLUX_SCHEMA'],
        'org' => @reader.raw_env['INFLUX_ORG'],
        'bucket' => @reader.raw_env['INFLUX_BUCKET'],
        'token' => influxdb_token,
      }.compact
    end

    # Support token aliasing: prefer INFLUX_TOKEN, fallback to INFLUX_ADMIN_TOKEN or INFLUX_TOKEN_WRITE
    def influxdb_token
      @reader.raw_env['INFLUX_TOKEN'].presence ||
        @reader.raw_env['INFLUX_ADMIN_TOKEN'].presence ||
        @reader.raw_env['INFLUX_TOKEN_WRITE']
    end

    # Preserve absolute host paths (e.g. Synology `/volume1/...`) so the stack
    # keeps pointing at the existing data directory after import. Relative
    # values and absolute paths that resolve to the default bind mount next
    # to compose.yaml are dropped — they match HELIOS's default anyway.
    def volume_path_data(section)
      mapping = VOLUME_PATH_ENVS.fetch(section)
      value = @reader.raw_env[mapping[:env_key]]
      return {} unless value&.start_with?('/')
      return {} if File.expand_path(value) == File.expand_path(mapping[:default_dir], @reader.stack_dir)

      { 'volume_path' => value }
    end

    # --- Sensors ---

    def sensors_data
      @sensors_data ||= begin
        dashboard_env = service_env('dashboard')
        explicit = dashboard_env
                   .select { |k, _| k.start_with?('INFLUX_SENSOR_') }
                   .compact_blank
                   .transform_keys { |k| k.delete_prefix('INFLUX_SENSOR_').downcase }
        # Legacy stacks omit most INFLUX_SENSOR_* and rely on the dashboard's
        # built-in fallback table — replicate it so the imported config matches
        # what the dashboard actually serves.
        LegacySensorAdapter.synthesize(dashboard_env).merge(explicit)
                           .select { |name, _| SensorRegistry.valid?(name) }
      end
    end

    # --- Reverse Proxy ---

    def reverse_proxy_data
      dashboard_env = service_env('dashboard')
      data = { 'trusted_proxy_ranges' => dashboard_env['TRUSTED_PROXY_RANGES'] }

      if @reader.services.key?('traefik') && (domain = extract_domain_from_dashboard_labels)
        data['app_domain'] = domain
        data['letsencrypt_email'] = @reader.raw_env['LETSENCRYPT_EMAIL']
        data.merge!(volume_path_data('reverse_proxy'))
      end

      data.compact.presence
    end

    def extract_domain_from_dashboard_labels
      rule_value = find_traefik_rule_label
      match = rule_value&.match(/Host\(`([^`]+)`\)/)
      match && match[1]
    end

    def find_traefik_rule_label
      labels = @reader.service('dashboard')&.dig('labels') || {}

      if labels.is_a?(Hash)
        labels.find { |k, _| k.include?('routers.dashboard.rule') }&.last
      else
        labels.find { |v| v.to_s.include?('routers.dashboard.rule') }
      end
    end

    def excluded_sensor_names
      csv_split(service_env('dashboard')['INFLUX_EXCLUDE_FROM_HOUSE_POWER']).map(&:downcase)
    end

    # --- Backup ---

    def backup_data
      return unless @reader.services.key?('postgresql-backup')

      {
        'postgresql' => image_hash_for('postgresql-backup'),
        'influxdb' => image_hash_for('influxdb-backup'),
        'aws_access_key_id' => @reader.raw_env['AWS_ACCESS_KEY_ID'],
        'aws_secret_access_key' => @reader.raw_env['AWS_SECRET_ACCESS_KEY'],
        'aws_region' => @reader.raw_env['AWS_REGION'],
        'aws_bucket' => @reader.raw_env['AWS_BUCKET'],
      }.compact
    end

    def image_hash_for(service_name)
      image = Compose.normalize_image(@reader.service(service_name)&.dig('image'))
      { 'image' => image } if image
    end

    # --- Ingest ---

    def ingest_section_data
      return unless balcony_sensor_name

      ingest_env = service_env('ingest')
      {
        'image' => Compose.normalize_image(@reader.service('ingest')&.dig('image')),
        'retention_hours' => ingest_env['RETENTION_HOURS'],
      }.merge(volume_path_data('ingest')).compact
    end
  end
end
