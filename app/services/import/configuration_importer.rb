module Import
  class ConfigurationImporter # rubocop:disable Metrics/ClassLength
    # Dashboard defaults that are always set in compose.yaml regardless of config.
    # Only store values that differ from these defaults.
    DASHBOARD_DEFAULTS = {
      'INFLUX_POLL_INTERVAL' => '5',
      'WEB_CONCURRENCY' => '0',
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
      sensor_persister.persist!(config)
      persist_unmanaged!(config)

      config
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
      @unmanaged_detector ||= UnmanagedDetector.new(@reader)
    end

    def sensor_persister
      @sensor_persister ||= SensorPersister.new(
        sensors_data:,
        devices: result[:devices],
        senec_enabled: senec_extractor.enabled?,
        mqtt_mappings: mqtt_extractor.enabled? ? mqtt_extractor.mappings : [],
      )
    end

    # --- Result building ---

    def build_result # rubocop:disable Metrics/MethodLength
      {
        system: system_data,
        postgresql: postgresql_data,
        influxdb: influxdb_data,
        redis: redis_data,
        watchtower: watchtower_data,
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

    def build_devices
      devices = []
      devices << senec_extractor.device_data if senec_extractor.enabled?
      devices.concat(shelly_extractor.device_data) if shelly_extractor.enabled?
      devices.concat(mqtt_extractor.device_data) if mqtt_extractor.enabled?
      distribute_house_power_exclusions(devices)
      devices
    end

    # --- Persistence ---

    def persist_singletons!(config)
      %i[system postgresql influxdb redis watchtower sensors forecast senec mqtt shelly reverse_proxy
         backup].each do |key|
        config.update(key.to_s, result[key]) if result[key]
      end
    end

    def persist_unmanaged!(config)
      unmanaged = result[:unmanaged]
      config.update_unmanaged(unmanaged) if unmanaged.present?
    end

    # --- System ---

    def system_data
      system_core_data
        .merge(system_dashboard_data)
        .merge('power_splitter_interval' => power_splitter_interval)
        .compact
    end

    def system_core_data
      dashboard_env = service_env('dashboard')

      {
        'timezone' => dashboard_env['TZ'],
        'installation_date' => dashboard_env['INSTALLATION_DATE'],
        'image' => Compose.normalize_image(@reader.service('dashboard')&.dig('image')),
        'admin_password' => @reader.raw_env['ADMIN_PASSWORD'],
        'secret_key_base' => @reader.raw_env['SECRET_KEY_BASE'],
      }
    end

    def system_dashboard_data
      dashboard_env = service_env('dashboard')

      system_optional_dashboard_data(dashboard_env)
        .merge(system_non_default_dashboard_data(dashboard_env))
    end

    def system_optional_dashboard_data(dashboard_env)
      {
        'app_host' => dashboard_env['APP_HOST'],
        'co2_emission_factor' => dashboard_env['CO2_EMISSION_FACTOR'],
        'force_ssl' => dashboard_env['FORCE_SSL'],
        'frame_ancestors' => dashboard_env['FRAME_ANCESTORS'],
        'ui_theme' => dashboard_env['UI_THEME'],
        'lockup_codeword' => dashboard_env['LOCKUP_CODEWORD'],
        'trusted_proxy_ranges' => dashboard_env['TRUSTED_PROXY_RANGES'],
      }
    end

    def system_non_default_dashboard_data(dashboard_env)
      DASHBOARD_DEFAULTS.each_with_object({}) do |(env_key, default), data|
        value = dashboard_env[env_key]
        data[env_key.downcase] = value if value.present? && value.to_s != default
      end
    end

    # --- Infrastructure services ---

    def redis_data
      image_data_for('redis')
    end

    def watchtower_data
      image_data_for('watchtower')
    end

    def postgresql_data
      {
        'image' => Compose.normalize_image(@reader.service('postgresql')&.dig('image')),
        'password' => @reader.raw_env['POSTGRES_PASSWORD'],
      }.compact
    end

    def influxdb_data
      # Support token aliasing: prefer INFLUX_TOKEN, fallback to INFLUX_ADMIN_TOKEN or INFLUX_TOKEN_WRITE
      token = @reader.raw_env['INFLUX_TOKEN'].presence ||
              @reader.raw_env['INFLUX_ADMIN_TOKEN'].presence ||
              @reader.raw_env['INFLUX_TOKEN_WRITE']

      {
        'image' => Compose.normalize_image(@reader.service('influxdb')&.dig('image')),
        'password' => @reader.raw_env['INFLUX_PASSWORD'],
        'org' => @reader.raw_env['INFLUX_ORG'],
        'bucket' => @reader.raw_env['INFLUX_BUCKET'],
        'token' => token,
      }.compact
    end

    # --- Sensors ---

    def sensors_data
      @sensors_data ||= begin
        dashboard_env = service_env('dashboard')
        dashboard_env
          .select { |k, _| k.start_with?('INFLUX_SENSOR_') }
          .compact_blank
          .transform_keys { |k| k.delete_prefix('INFLUX_SENSOR_').downcase }
      end
    end

    # --- Reverse Proxy ---

    def reverse_proxy_data
      return unless @reader.services.key?('traefik')

      domain = extract_domain_from_dashboard_labels
      return unless domain

      {
        'app_domain' => domain,
        'letsencrypt_email' => @reader.raw_env['LETSENCRYPT_EMAIL'],
      }.compact
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

    # --- House power exclusions ---

    def distribute_house_power_exclusions(devices)
      excluded = excluded_sensor_names
      return if excluded.empty?

      consumer_index = 0
      devices.each do |device|
        sensor = sensor_name_for_device(device, consumer_index)
        consumer_index += 1 if device[:type] == 'consumer'
        next unless sensor

        device[:data]['exclude_from_house_power'] = true if excluded.include?(sensor.upcase)
      end
    end

    def excluded_sensor_names
      dashboard_env = service_env('dashboard')
      value = dashboard_env['INFLUX_EXCLUDE_FROM_HOUSE_POWER']
      return [] if value.blank?

      value.to_s.split(',').map(&:strip)
    end

    def sensor_name_for_device(device, consumer_index)
      case device[:type]
      when 'heatpump' then 'HEATPUMP_POWER'
      when 'wallbox' then 'WALLBOX_POWER'
      when 'consumer' then format('CUSTOM_POWER_%02d', consumer_index + 1)
      end
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

    # --- Power-Splitter ---

    def power_splitter_interval
      ps_env = service_env('power-splitter')
      ps_env['POWER_SPLITTER_INTERVAL']
    end

    # --- Shared helpers ---

    def service_env(name)
      @service_envs ||= {}
      @service_envs[name] ||= @reader.service(name)&.dig('environment') || {}
    end

    def image_data_for(service_name)
      image = Compose.normalize_image(@reader.service(service_name)&.dig('image'))
      { 'image' => image }.compact
    end
  end
end
