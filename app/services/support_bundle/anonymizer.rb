module SupportBundle
  # Redacts a small, explicit whitelist of variables from config files
  # so the bundle can be shared in a public support forum. Placeholders
  # are derived from the key name (e.g. `dummy_postgres_password`)
  # so the stack still starts when the bundle is replayed locally. Add
  # more variables here on demand.
  module Anonymizer
    ENV_KEYS = %w[
      ADMIN_PASSWORD
      AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY
      FORECAST_LATITUDE
      FORECAST_LONGITUDE
      FORECAST_SOLAR_APIKEY
      INFLUX_PASSWORD
      INFLUX_TOKEN
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
    ].to_set.freeze

    YAML_KEYS = {
      'system' => %w[admin_password secret_key_base lockup_codeword],
      'postgresql' => %w[password],
      'influxdb' => %w[password token],
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

    # Non-string fields need realistic dummies so the replayed stack can
    # parse them. Listed under both the ENV and YAML spelling because the
    # env var (SENEC_SYSTEM_ID) and the YAML leaf (senec.system_id) reach
    # the lookup with different names.
    DUMMY_VALUES = {
      'forecast_latitude' => '50.0',
      'forecast_longitude' => '10.0',
      'senec_system_id' => '0',
      'system_id' => '0',
    }.freeze

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

      YAML.dump(data)
    end

    def redact_fields(hash, keys)
      return unless hash.is_a?(Hash)

      keys.each { |key| hash[key] = placeholder_for(key) if hash[key].present? }
    end

    def anonymize_env_line(line)
      return line if line.lstrip.start_with?('#')

      match = line.match(ENV_LINE)
      return line unless match
      return line unless ENV_KEYS.include?(match[:key].upcase)
      return line if match[:value].empty? || match[:value].start_with?('${')

      "#{match[:prefix]}#{match[:key]}=#{placeholder_for(match[:key])}#{match[:trailing]}"
    end

    def placeholder_for(key)
      normalized = key.to_s.downcase
      DUMMY_VALUES[normalized] || "dummy_#{normalized}"
    end
  end
end
