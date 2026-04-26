module Import
  class ConfigurationImporter
    class UnmanagedDetector # rubocop:disable Metrics/ClassLength
      # All .env variable keys that HELIOS manages (generates in .env)
      MANAGED_ENV_KEYS = %w[
        TZ INSTALLATION_DATE ADMIN_PASSWORD SECRET_KEY_BASE
        APP_HOST INFLUX_POLL_INTERVAL CO2_EMISSION_FACTOR
        FORCE_SSL WEB_CONCURRENCY FRAME_ANCESTORS UI_THEME
        INFLUX_EXCLUDE_FROM_HOUSE_POWER
        LOCKUP_CODEWORD TRUSTED_PROXY_RANGES
        POWER_SPLITTER_INTERVAL
        RETENTION_HOURS STATS_PASSWORD
        WATCHTOWER_POLL_INTERVAL
        POSTGRES_PASSWORD
        INFLUX_PASSWORD INFLUX_ORG INFLUX_BUCKET INFLUX_TOKEN
        INFLUX_ADMIN_TOKEN INFLUX_TOKEN_READ INFLUX_TOKEN_WRITE
        INFLUX_MEASUREMENT INFLUX_MEASUREMENT_SENEC INFLUX_MEASUREMENT_FORECAST
        INFLUX_MEASUREMENT_SHELLY INFLUX_MEASUREMENT_MQTT
        INFLUX_MODE INFLUX_POWER_DATA_TYPE
        APP_DOMAIN LETSENCRYPT_EMAIL
        AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_BUCKET
        SENEC_ADAPTER SENEC_HOST SENEC_SCHEMA SENEC_LANGUAGE SENEC_INTERVAL
        SENEC_USERNAME SENEC_PASSWORD SENEC_TOTP_URI SENEC_SYSTEM_ID SENEC_IGNORE
        SENEC_REQUEST_MODE
        FORECAST_PROVIDER FORECAST_LATITUDE FORECAST_LONGITUDE
        FORECAST_DECLINATION FORECAST_AZIMUTH FORECAST_KWP
        FORECAST_CONFIGURATIONS FORECAST_INTERVAL
        FORECAST_DAMPING_MORNING FORECAST_DAMPING_EVENING
        FORECAST_HORIZON FORECAST_INVERTER
        FORECAST_SOLAR_APIKEY SOLCAST_APIKEY SOLCAST_SITE
        PVNODE_APIKEY PVNODE_PAID PVNODE_EXTRA_PARAMS
        SHELLY_HOST SHELLY_INTERVAL SHELLY_PASSWORD
        SHELLY_CLOUD_SERVER SHELLY_AUTH_KEY SHELLY_DEVICE_ID SHELLY_INVERT_POWER
        MQTT_HOST MQTT_PORT MQTT_SSL MQTT_USERNAME MQTT_PASSWORD
      ].freeze

      # Infrastructure .env keys that HELIOS doesn't generate but are well-known
      # SOLECTRUS vars. These are suppressed from unmanaged to avoid noise.
      INFRASTRUCTURE_ENV_KEYS = %w[
        INFLUX_HOST INFLUX_SCHEMA INFLUX_PORT INFLUX_VOLUME_PATH INFLUX_USERNAME
        DB_HOST DB_USER DB_PASSWORD DB_VOLUME_PATH DB_DATABASE
        REDIS_URL REDIS_VOLUME_PATH
        INGEST_VOLUME_PATH TRAEFIK_VOLUME_PATH
      ].freeze

      # Legacy SOLECTRUS keys that HELIOS absorbs at import time via
      # LegacySensorAdapter and MqttExtractor::DEPRECATED_TOPIC_VARS — once
      # translated into sensors/mappings, the originals would only cause noise
      # if re-emitted.
      LEGACY_CONSUMED_ENV_KEYS = %w[
        INFLUX_MEASUREMENT_PV
        MQTT_FLIP_GRID_POW MQTT_FLIP_BAT_POWER
      ].freeze

      INTERPOLATION_RE = /\$\{([A-Z_][A-Z0-9_]*)\}/

      # HELIOS-core env vars that belong to the helios container only —
      # never attach them to an unmanaged service even if it uses env_file.
      HELIOS_CORE_ENV_KEYS = %w[ADMIN_PASSWORD SECRET_KEY_BASE].freeze

      def initialize(reader, known_measurements: [])
        @reader = reader
        @known_measurements = known_measurements.to_set
      end

      def detect
        data = {}

        services = normalized_unmanaged_services
        data['services'] = services if services.present?

        orphaned = detect_orphaned_env_vars(services || {})
        data['env_vars'] = orphaned if orphaned.present?

        data.presence
      end

      private

      def normalized_unmanaged_services
        raw = @reader.raw_compose['services'] || {}
        unmanaged = raw.reject { |_name, config| managed_service?(config) }

        pre = unmanaged.transform_values { |config| extract_referenced(config) }
        distribute_env_file_orphans!(pre)
        pre.transform_values { |service| finalize_service(service) }.presence
      end

      # First-pass extraction: split the raw compose service config into
      # a stable shape we can enrich in a second pass.
      #
      #   declared  — names directly listed in `environment:` (the service's
      #               own contract — preserved verbatim, not extended)
      #   referenced — declared + names read from ${VAR} interpolations
      #               (needed in .env for docker compose config resolution,
      #               but must not be injected into the compose environment)
      def extract_referenced(config)
        result = config.dup
        env_file_used = expand_env_file!(result)
        declared = declared_env_names(result['environment'])
        referenced = referenced_env_names(result).subtract(HELIOS_CORE_ENV_KEYS)

        {
          raw: result,
          declared: declared,
          referenced: referenced,
          inline: explicit_value_entries(result['environment']),
          value_names: value_carrying_names(result['environment']),
          absorbs_env_file: env_file_used,
        }
      end

      # Services that had `env_file: .env` inherit any raw .env key that no
      # other service already references. With multiple such services, orphans
      # are distributed to all of them (mirrors Docker's env_file semantics).
      # Only `env_file` services get new names injected into their environment
      # list; regular services keep their declared list untouched.
      def distribute_env_file_orphans!(services)
        claimed = services.values.flat_map { |s| s[:referenced].to_a }.to_set
        orphans = promotable_raw_env_keys - claimed

        services.each_value do |service|
          next unless service[:absorbs_env_file]

          service[:declared].merge(orphans)
          service[:referenced].merge(orphans)
        end
      end

      # Second pass: keep the service's declared environment list intact, only
      # sorting its entries. Collect values for every referenced var (declared
      # or interpolated) so they survive the round-trip via service env_values.
      def finalize_service(service)
        result = service[:raw]
        name_only = (service[:declared] - service[:value_names]).to_a

        result['environment'] = sort_env_entries(service[:inline] + name_only)
        result['env_values'] = collect_env_values(service[:referenced]).presence
        result.compact
      end

      # Names that appear directly in `environment:` as either "NAME" or
      # "NAME=value" — the service's own contract.
      def declared_env_names(environment)
        names = Set.new
        Array(environment).each do |entry|
          case entry
          when String
            name = entry.split('=', 2).first
            names << name if valid_env_name?(name)
          when Hash
            entry.each_key { |k| names << k.to_s if valid_env_name?(k.to_s) }
          end
        end
        names
      end

      # Detach env_file: .env. Returns true if it was present.
      def expand_env_file!(config)
        files = Array(config['env_file'])
        return false if files.empty?

        used_full_env = files.any? { |f| f.is_a?(String) ? f == '.env' : f['path'] == '.env' }
        config.delete('env_file') if used_full_env
        used_full_env
      end

      # Names referenced either directly in environment entries or via
      # ${VAR} interpolations inside their values.
      def referenced_env_names(config)
        names = Set.new
        Array(config['environment']).each do |entry|
          case entry
          when String
            name, value = entry.split('=', 2)
            names << name if valid_env_name?(name)
            names.merge(scan_interpolations(value)) if value
          when Hash
            entry.each do |k, v|
              names << k.to_s if valid_env_name?(k.to_s)
              names.merge(scan_interpolations(v.to_s))
            end
          end
        end
        names
      end

      def scan_interpolations(value)
        value.to_s.scan(INTERPOLATION_RE).flatten
      end

      def valid_env_name?(name)
        name.to_s.match?(/\A[A-Z_][A-Z0-9_]*\z/)
      end

      # Raw .env keys eligible to be attached to a service using env_file: .env.
      # HELIOS-core secrets stay out.
      def promotable_raw_env_keys
        @promotable_raw_env_keys ||=
          @reader.raw_env.to_h.keys.to_set - HELIOS_CORE_ENV_KEYS
      end

      # Entries of the form "NAME=value" that carry a value — kept as-is.
      def explicit_value_entries(environment)
        Array(environment).select { |e| e.is_a?(String) && e.include?('=') }
      end

      def value_carrying_names(environment)
        explicit_value_entries(environment).filter_map { |e| e.split('=', 2).first }.to_set
      end

      # Values for name-only environment entries. Keys that HELIOS renders
      # in a managed .env section are skipped — the compose `- NAME` reference
      # picks them up at docker runtime.
      def collect_env_values(names)
        raw = @reader.raw_env.to_h
        managed = managed_env_keys_set
        names.each_with_object({}) do |name, values|
          next if managed.include?(name)

          value = raw[name]
          values[name] = value if value.present?
        end
      end

      # Env-var sort order:
      #   1. TZ
      #   2. INFLUX_* alphabetical
      #   3. MAPPING_<N>_* numeric by N, alphabetical within
      #   4. Everything else alphabetical (service-specific prefixes, etc.)
      # Entries carrying a value ("NAME=...") sort by their NAME part.
      def sort_env_entries(entries)
        entries.sort_by { |entry| sort_key(entry) }
      end

      def sort_key(entry)
        name = entry.split('=', 2).first
        return [0] if name == 'TZ'
        return [1, name] if name.start_with?('INFLUX_')
        return [2, mapping_index(name), name] if name.start_with?('MAPPING_')

        [3, name]
      end

      def mapping_index(name)
        (name[/\AMAPPING_(\d+)_/, 1] || '0').to_i
      end

      # Orphaned env vars: present in raw .env but not attached to any service
      # or managed by HELIOS core.
      def detect_orphaned_env_vars(services)
        attached = services.values.flat_map { |cfg| Array(cfg['env_values']&.keys) }.to_set
        managed = managed_env_keys_set + attached

        @reader
          .raw_env
          .to_h
          .reject do |key, value|
            managed.include?(key) ||
              managed_shelly_env_key?(key) ||
              redundant_measurement_alias?(key, value)
          end
          .presence
      end

      # User-defined INFLUX_MEASUREMENT_* vars are pure naming aliases — the
      # SOLECTRUS stack never reads them. If the value is already captured as
      # a measurement in the imported sensor config, the alias is redundant
      # and would only clutter the unmanaged section.
      def redundant_measurement_alias?(key, value)
        key.start_with?('INFLUX_MEASUREMENT_') && @known_measurements.include?(value)
      end

      # Detect by image rather than service name, so legacy installations that use
      # historical names like 'app' (for SOLECTRUS) or 'db' (for PostgreSQL) are
      # recognized as managed and get migrated to canonical names on export.
      def managed_service?(config)
        StackReader.managed_image?(config['image']) ||
          ShellyExtractor.shelly_image?(config['image'])
      end

      # Pattern-named shelly-collector env vars: per-device helpers from both
      # multi-service stacks (SHELLY_DEVICE_ID_FRIDGE, INFLUX_MEASUREMENT_SHELLY_FRIDGE)
      # and single-service collectors_only stacks (SHELLY_HOST_FRIDGE, absorbed
      # into shelly.devices on import).
      def managed_shelly_env_key?(key)
        key.start_with?('SHELLY_DEVICE_ID_', 'INFLUX_MEASUREMENT_SHELLY_', 'SHELLY_HOST_')
      end

      def managed_env_keys_set
        @managed_env_keys_set ||= (
          MANAGED_ENV_KEYS +
            INFRASTRUCTURE_ENV_KEYS +
            LEGACY_CONSUMED_ENV_KEYS +
            MqttExtractor::DEPRECATED_TOPIC_VARS.keys +
            MqttExtractor::DEPRECATED_SPLIT_VARS.keys +
            SensorRegistry::SENSORS.keys.map { |s| "INFLUX_SENSOR_#{s.upcase}" } +
            forecast_indexed_env_keys +
            pvnode_indexed_env_keys +
            mqtt_mapping_env_keys
        ).to_set
      end

      def forecast_indexed_env_keys
        (0..3).flat_map do |i|
          ["FORECAST_#{i}_DECLINATION", "FORECAST_#{i}_AZIMUTH", "FORECAST_#{i}_KWP", "SOLCAST_#{i}_SITE"]
        end
      end

      def pvnode_indexed_env_keys
        (0..3).map { |i| "PVNODE_#{i}_EXTRA_PARAMS" }
      end

      def mqtt_mapping_env_keys
        # Detect all MAPPING_N_* keys from the raw .env
        @reader.raw_env.to_h.keys.grep(/\AMAPPING_\d+_/)
      end
    end
  end
end
