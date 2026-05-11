module SupportBundle
  # Redacts secrets from config files so the bundle can be shared in a
  # public support forum. Placeholders are derived from the key name
  # (e.g. `dummy_postgres_password`) so the stack still starts when the
  # bundle is replayed locally.
  #
  # Recognition has two layers: the explicit `ENV_KEYS` / `YAML_KEYS`
  # lists drive placeholder shape, log-redaction behavior, and special
  # dummies (lat/lng, SENEC_SYSTEM_ID); `SENSITIVE_KEY_PATTERN` is a
  # name-based catch-all for vendor-specific keys HELIOS has never seen,
  # especially inside unmanaged-service `env_values`.
  module Anonymizer # rubocop:disable Metrics/ModuleLength
    ENV_KEYS = %w[
      ADMIN_PASSWORD
      AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY
      FORECAST_LATITUDE
      FORECAST_LONGITUDE
      FORECAST_SOLAR_APIKEY
      INFLUX_ADMIN_TOKEN
      INFLUX_PASSWORD
      INFLUX_TOKEN
      INFLUX_TOKEN_READ
      INFLUX_TOKEN_READWRITE
      INFLUX_TOKEN_WRITE
      LOCKUP_CODEWORD
      MQTT_PASSWORD
      MQTT_USERNAME
      POSTGRES_PASSWORD
      PVNODE_APIKEY
      SECRET_KEY_BASE
      SENEC_PASSWORD
      SENEC_SYSTEM_ID
      SENEC_TOTP_URI
      SENEC_USERNAME
      SHELLY_AUTH_KEY
      SHELLY_PASSWORD
      SOLCAST_APIKEY
      TIBBER_TOKEN
    ].to_set.freeze

    YAML_KEYS = {
      'system' => %w[admin_password secret_key_base],
      'dashboard' => %w[lockup_codeword],
      'postgresql' => %w[password],
      'influxdb' => %w[password token token_admin token_readwrite token_write token_read],
      'mqtt' => %w[mqtt_username mqtt_password],
      'senec' => %w[username password totp_uri system_id],
      'shelly' => %w[password auth_key],
      'backup' => %w[aws_access_key_id aws_secret_access_key],
      'forecast' => %w[
        forecast_latitude forecast_longitude
        forecast_solar_apikey forecast_solcast_api_key forecast_pvnode_apikey
      ],
    }.freeze

    # Per-sensor fields to redact inside the dynamic `sensors:` section.
    SENSOR_KEYS = %w[shelly_password].freeze

    # Catch-all pattern for unrecognized secrets that follow common
    # naming conventions. Kept narrow so harmless keys (`SENEC_LANGUAGE`,
    # `MAPPING_<N>_JSON_KEY`, `INFLUX_USERNAME=admin`) don't get caught.
    # `API_?KEY` covers both `APIKEY` and `API_KEY` spellings.
    SENSITIVE_KEY_PATTERN = /PASSWORD|SECRET|TOKEN|API_?KEY|AUTH_KEY|ACCESS_KEY|PRIVATE_KEY/

    # Coordinates may surface in container logs with extra trailing digits
    # (Float arithmetic in the forecast collector turns 50.92264 into
    # 50.922642249999996), so they need a regex tolerant to those tails
    # instead of a literal match when scrubbing log output.
    NUMERIC_KEYS = %w[FORECAST_LATITUDE FORECAST_LONGITUDE].to_set.freeze

    # Non-string fields need parseable dummies so the replayed stack can
    # load them. Listed under both the ENV and YAML spelling because the
    # env var (SENEC_SYSTEM_ID) and the YAML leaf (senec.system_id) reach
    # the lookup with different names. Coordinates default to 0.00000 —
    # a syntactically valid value that is obviously a placeholder at a
    # glance, so reviewers don't mistake it for a real location.
    DUMMY_VALUES = {
      'forecast_latitude' => '0.00000',
      'forecast_longitude' => '0.00000',
      'senec_system_id' => '0',
      'system_id' => '0',
    }.freeze

    # Values shorter than this are skipped when scrubbing log content to
    # avoid false positives on common words (e.g. a 3-letter username
    # would otherwise be replaced everywhere it appears as plain text).
    LOG_REDACTION_MIN_LENGTH = 4

    ENV_LINE = /\A(?<prefix>\s*-?\s*)(?<key>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*?)(?<trailing>\s*)\z/

    module_function

    def anonymize_env_style(content)
      content.each_line.map { |line| anonymize_env_line(line) }.join
    end

    def anonymize_yaml(content)
      data = YAML.safe_load(content, permitted_classes: [Date])
      return content unless data.is_a?(Hash)

      YAML_KEYS.each do |section, keys|
        redact_fields(data[section], keys)
      end

      data['sensors']&.each_value { |sensor| redact_fields(sensor, SENSOR_KEYS) }

      data.dig('_unmanaged', 'services')&.each_value do |service|
        redact_unmanaged_env_values(service)
      end

      YAML.dump(data)
    end

    def redact_fields(hash, keys)
      return unless hash.is_a?(Hash)

      keys.each { |key| hash[key] = placeholder_for(key) if hash[key].present? }
    end

    # Unmanaged services keep their env vars as a free-form `env_values`
    # hash, so secrets land here under their original spelling rather than
    # under any name HELIOS knows.
    def redact_unmanaged_env_values(service)
      values = service.is_a?(Hash) ? service['env_values'] : nil
      return unless values.is_a?(Hash)

      values.each do |key, value|
        next unless sensitive_key?(key)
        next if value.blank?
        next if value.is_a?(String) && value.start_with?('${')

        values[key] = placeholder_for(key)
      end
    end

    def anonymize_env_line(line)
      match = parse_sensitive_env_line(line)
      return line unless match

      "#{match[:prefix]}#{match[:key]}=#{placeholder_for(match[:key])}#{match[:trailing]}"
    end

    def placeholder_for(key)
      normalized = key.to_s.downcase
      DUMMY_VALUES[normalized] || "dummy_#{normalized}"
    end

    def sensitive_key?(key)
      upper = key.to_s.upcase
      ENV_KEYS.include?(upper) || SENSITIVE_KEY_PATTERN.match?(upper)
    end

    # Extracts (pattern, placeholder) pairs for every whitelisted env value
    # that should be scrubbed from container log output. Coordinates use a
    # regex tolerant to Float-precision tails; opaque secrets use literal
    # substring matches.
    def log_redactions(env_content)
      env_content.each_line.filter_map { |line| line_redaction(line) }
    end

    # Applies redaction pairs to free-form text (e.g. container logs) so
    # the same secrets present in .env are masked when they leak through
    # other channels.
    def anonymize_text(content, redactions)
      redactions.reduce(content) do |result, (pattern, replacement)|
        result.gsub(pattern, replacement)
      end
    end

    def line_redaction(line)
      match = parse_sensitive_env_line(line)
      return nil unless match

      key = match[:key].upcase
      pattern = redaction_pattern(key, match[:value])
      pattern && [pattern, placeholder_for(key)]
    end

    def parse_sensitive_env_line(line)
      return nil if line.lstrip.start_with?('#')

      match = line.match(ENV_LINE)
      return nil unless match
      return nil unless sensitive_key?(match[:key])
      return nil if match[:value].empty? || match[:value].start_with?('${')

      match
    end

    def redaction_pattern(key, value)
      return /\b#{Regexp.escape(value)}\d*\b/ if NUMERIC_KEYS.include?(key)
      return nil if value.length < LOG_REDACTION_MIN_LENGTH

      value
    end
  end
end
