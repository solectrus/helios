require 'ipaddr'

module SupportBundle
  # Redacts sensitive data from config files so the bundle can be shared in
  # a public support forum. Strings are masked to a same-length run of a
  # single uppercase letter ("geheim" → "AAAAAA") so no original character
  # leaks. A per-bundle registry guarantees the same value always gets the
  # same mask across compose.yaml, .env, config.yaml and container logs —
  # so support can still tell "INFLUX_TOKEN and INFLUX_TOKEN_WRITE share a
  # value" or "this domain appears in two places". Coordinates are softened
  # (integer part kept, decimals zeroed) because the integer part alone
  # only narrows location to a ~100 km band — useful for diagnostics.
  #
  # Recognition has three layers: explicit `ENV_KEYS` / `YAML_KEYS` cover
  # always-redact secrets; `BUCKET_KEYS` cover identifiers (bucket/org names)
  # that may leak location even though they aren't secret; `HOST_KEYS` cover
  # hostnames, redacted only when they're public FQDNs — private IPs and
  # container names stay so support can still see the network topology.
  # `SENSITIVE_KEY_PATTERN` is a name-based catch-all for vendor-specific
  # keys HELIOS has never seen, especially inside unmanaged-service `env_values`.
  #
  # `SAFE_VALUES` is a small allowlist of well-known, non-identifying words
  # ("solectrus", "SENEC") kept visible when they appear as a non-secret
  # identifier (org/bucket), so the stock naming stays readable. It never
  # un-redacts a secret — the check sits on the identifier paths only.
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
      SOLCAST_0_SITE
      SOLCAST_1_SITE
      SOLCAST_APIKEY
      SOLCAST_SITE
      TIBBER_TOKEN
    ].to_set.freeze

    # Identifiers that aren't secret but may give away who/where the user is
    # (custom bucket like "berlin-pv"). Redacted unless the value is in the
    # SAFE_VALUES allowlist below.
    BUCKET_KEYS = %w[INFLUX_BUCKET INFLUX_ORG].to_set.freeze

    # Well-known, non-identifying org/bucket names kept visible: the SOLECTRUS
    # default name ("solectrus", the default org/bucket) and the vendor name
    # ("SENEC"). These reveal nothing about who or where the user is, and
    # keeping them lets support see the stock naming at a glance. Applied only
    # to the non-secret identifier paths (BUCKET_KEYS / YAML_BUCKET_KEYS), so
    # it can never expose a secret. Matched case-insensitively against the
    # *whole* value, so a custom name like "my-solectrus-bucket" or
    # "berlin-pv" is still masked.
    SAFE_VALUES = %w[solectrus senec].to_set.freeze

    # Hostnames are only redacted when the value is a public FQDN. Private
    # IPs (RFC 1918), loopback and Docker container names stay as-is — they
    # are useful for diagnostics and don't leak location.
    HOST_KEYS = %w[APP_HOST INFLUX_HOST MQTT_HOST SENEC_HOST SHELLY_HOST].to_set.freeze

    # Local/reserved zones that look like an FQDN but never leave the LAN.
    # `.fritz.box` (AVM router default), `.local` (mDNS), `.lan/.home/.intern*`
    # (de-facto LAN suffixes) — keeping them visible helps support diagnose
    # network setups without exposing the user's public domain.
    LOCAL_HOST_SUFFIXES = %w[.local .lan .home .box .internal .intern .localhost].freeze

    YAML_KEYS = {
      'system' => %w[admin_password secret_key_base],
      'dashboard' => %w[lockup_codeword],
      'postgresql' => %w[password],
      'influxdb' => %w[password token token_admin token_readwrite token_write token_read],
      'mqtt' => %w[mqtt_username mqtt_password],
      'tibber' => %w[token],
      'senec' => %w[username password totp_uri system_id],
      'shelly' => %w[password auth_key],
      'backup' => %w[aws_access_key_id aws_secret_access_key],
      'forecast' => %w[
        forecast_latitude forecast_longitude
        forecast_solar_apikey forecast_solcast_api_key forecast_pvnode_apikey
        forecast_solcast_id1 forecast_solcast_id2
      ],
    }.freeze

    # YAML identifiers redacted unless the value is in SAFE_VALUES — same
    # idea as `BUCKET_KEYS` on the .env side.
    YAML_BUCKET_KEYS = { 'influxdb' => %w[bucket org] }.freeze

    # YAML host fields redacted only when the value is a public FQDN.
    YAML_HOST_KEYS = {
      'influxdb' => %w[host],
      'mqtt' => %w[host],
      'senec' => %w[host],
      'shelly' => %w[host],
    }.freeze

    # Per-sensor fields to redact inside the dynamic `sensors:` section.
    SENSOR_KEYS = %w[shelly_password].freeze

    # Per-sensor host fields redacted only when the value is a public FQDN.
    SENSOR_HOST_KEYS = %w[shelly_host senec_host mqtt_host].freeze

    # Catch-all pattern for unrecognized secrets that follow common
    # naming conventions. Kept narrow so harmless keys (`SENEC_LANGUAGE`,
    # `MAPPING_<N>_JSON_KEY`, `INFLUX_USERNAME=admin`) don't get caught.
    # `API_?KEY` covers both `APIKEY` and `API_KEY` spellings.
    SENSITIVE_KEY_PATTERN = /PASSWORD|SECRET|TOKEN|API_?KEY|AUTH_KEY|ACCESS_KEY|PRIVATE_KEY/

    # Coordinates get a softer mask (integer part kept, decimals zeroed)
    # — these keys flag values that should go through coord_mask instead
    # of the standard letter mask, both in .env/YAML and in container logs.
    COORD_KEYS = %w[FORECAST_LATITUDE FORECAST_LONGITUDE].to_set.freeze

    # SENEC_SYSTEM_ID is a numeric identifier the replayed stack must parse
    # as an Integer. Listed under both the ENV and YAML spelling because the
    # env var (SENEC_SYSTEM_ID) and the YAML leaf (senec.system_id) reach
    # the lookup with different names. The all-letter mask would break
    # parsing, so it gets a fixed '0' placeholder instead.
    INTEGER_PLACEHOLDER_KEYS = %w[senec_system_id system_id].to_set.freeze

    # Values shorter than this are skipped when scrubbing log content to
    # avoid false positives on common words (e.g. a 3-letter username
    # would otherwise be replaced everywhere it appears as plain text).
    LOG_REDACTION_MIN_LENGTH = 4

    # The standard mask is always exactly this many letters wide — the same
    # length regardless of the original value, so nothing about the input's
    # shape (or length) leaks through the bundle.
    MASK_LENGTH = 5

    ENV_LINE = /\A(?<prefix>\s*-?\s*)(?<key>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*?)(?<trailing>\s*)\z/

    @registry = {} # rubocop:disable ThreadSafety/MutableClassInstanceVariable

    module_function

    # Clears the per-bundle value→letter mapping. Call once at the start of
    # building a support bundle so masks are reproducible inside the bundle
    # but don't bleed across runs.
    def reset_registry!
      @registry = {} # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def registry
      @registry # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def anonymize_env_style(content)
      content.each_line.map { |line| anonymize_env_line(line) }.join
    end

    def anonymize_yaml(content)
      data = YAML.safe_load(content, permitted_classes: [Date])
      return content unless data.is_a?(Hash)

      redact_yaml_sections(data)
      redact_yaml_sensors(data['sensors'])
      data.dig('_unmanaged', 'services')&.each_value { |service| redact_unmanaged_env_values(service) }

      YAML.dump(data)
    end

    def redact_yaml_sections(data)
      YAML_KEYS.each { |section, keys| redact_fields(data[section], keys) }
      YAML_BUCKET_KEYS.each { |section, keys| redact_bucket_fields(data[section], keys) }
      YAML_HOST_KEYS.each { |section, keys| redact_host_fields(data[section], keys) }
    end

    def redact_yaml_sensors(sensors)
      sensors&.each_value do |sensor|
        redact_fields(sensor, SENSOR_KEYS)
        redact_host_fields(sensor, SENSOR_HOST_KEYS)
      end
    end

    def redact_fields(hash, keys)
      return unless hash.is_a?(Hash)

      keys.each do |key|
        value = hash[key]
        hash[key] = placeholder_for(key, value) if value.present?
      end
    end

    def redact_host_fields(hash, keys)
      return unless hash.is_a?(Hash)

      keys.each do |key|
        value = hash[key]
        hash[key] = placeholder_for(key, value) if value.present? && public_hostname?(value)
      end
    end

    # Like redact_fields, but keeps well-known org/bucket names visible
    # (see SAFE_VALUES) — the YAML counterpart to the BUCKET_KEYS gate in
    # `line_sensitive?`.
    def redact_bucket_fields(hash, keys)
      return unless hash.is_a?(Hash)

      keys.each do |key|
        value = hash[key]
        hash[key] = placeholder_for(key, value) if value.present? && !safe_value?(value)
      end
    end

    # Unmanaged services keep their env vars as a free-form `env_values`
    # hash, so secrets land here under their original spelling rather than
    # under any name HELIOS knows.
    def redact_unmanaged_env_values(service)
      values = service.is_a?(Hash) ? service['env_values'] : nil
      return unless values.is_a?(Hash)

      values.each do |key, value|
        next if value.blank?
        next if value.is_a?(String) && value.start_with?('${')
        next unless line_sensitive?(key, value.to_s)

        values[key] = placeholder_for(key, value)
      end
    end

    def anonymize_env_line(line)
      match = parse_sensitive_env_line(line)
      return line unless match

      "#{match[:prefix]}#{match[:key]}=#{placeholder_for(match[:key], match[:value])}#{match[:trailing]}"
    end

    # Returns the right kind of placeholder for the key/value pair:
    # - Coordinates: `52.51627` → `52.00000` (integer part kept).
    # - Integer IDs: fixed `'0'` so the replayed stack can parse it.
    # - Everything else: same-length run of an uppercase letter, with the
    #   letter chosen so the same input value always maps to the same mask.
    def placeholder_for(key, value)
      normalized = key.to_s.downcase
      return coord_mask(value) if COORD_KEYS.include?(key.to_s.upcase)
      return '0' if INTEGER_PLACEHOLDER_KEYS.include?(normalized)

      mask(value)
    end

    # The standard mask: a fixed-width run of a single uppercase letter so
    # the dummy is unmistakable at a glance and gives away neither the
    # value nor its length. Registry-backed so cross-file references stay
    # linkable (same value → same letter, throughout the bundle).
    def mask(value)
      str = value.to_s
      return str if str.empty?

      letter = (@registry[str] ||= assign_letter) # rubocop:disable ThreadSafety/ClassInstanceVariable
      letter * MASK_LENGTH
    end

    # Lat/Lng: keep the integer (and sign) so the rough latitude band is
    # visible for diagnostics, zero everything after the decimal point.
    # Length is preserved so `52.51627` → `52.00000` and `52.5162799` (a
    # float-precision tail seen in forecast logs) → `52.0000000`.
    def coord_mask(value)
      match = value.to_s.match(/\A(-?\d+)\.(\d+)\z/)
      return mask(value) unless match

      "#{match[1]}.#{'0' * match[2].length}"
    end

    def assign_letter
      ('A'.ord + (@registry.size % 26)).chr # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def sensitive_key?(key)
      upper = key.to_s.upcase
      ENV_KEYS.include?(upper) || SENSITIVE_KEY_PATTERN.match?(upper)
    end

    # True for well-known, non-identifying words ("solectrus", "SENEC") that
    # stay visible when they appear as a non-secret identifier (org/bucket).
    # Whole-value, case-insensitive match — a custom name that merely contains
    # the word ("my-solectrus-bucket") is still masked. Only consulted on
    # identifier paths, never for secrets.
    def safe_value?(value)
      SAFE_VALUES.include?(value.to_s.strip.downcase)
    end

    # True for hostnames that point outside the LAN. Comma-separated lists
    # (e.g. SHELLY_HOST) count as public when any element is public.
    def public_hostname?(value)
      return false if value.blank?

      value.to_s.split(',').any? { |part| public_single_hostname?(part.strip) }
    end

    def public_single_hostname?(value)
      # .env doesn't really support inline comments — Docker Compose treats
      # `KEY=192.168.1.10 # note` as a literal value with the comment baked
      # in. Real users still write this; tolerate it here so the leading IP
      # is recognized as private and the line stays untouched.
      hostname = value.to_s.split.first
      return false if hostname.blank?
      return false unless hostname.include?('.')
      return false if ip_address?(hostname)

      downcased = hostname.downcase
      LOCAL_HOST_SUFFIXES.none? { |suffix| downcased.end_with?(suffix) }
    end

    def ip_address?(value)
      IPAddr.new(value)
      true
    rescue IPAddr::InvalidAddressError
      false
    end

    # Extracts (pattern, replacement) pairs for every whitelisted env value
    # that should be scrubbed from container log output. Coordinates use a
    # regex tolerant to Float-precision tails and a callable replacement so
    # the integer part of each match is preserved; opaque secrets use literal
    # substring matches; SHELLY_HOST lists fan out into one pair per public
    # entry so each gets its own mask.
    def log_redactions(env_content)
      env_content.each_line.flat_map { |line| line_redactions(line) }
    end

    # Applies redaction pairs to free-form text (e.g. container logs) so
    # the same secrets present in .env are masked when they leak through
    # other channels. Replacement may be a String or a callable — the
    # callable form lets coordinate matches keep their original integer
    # part regardless of trailing float-precision digits.
    def anonymize_text(content, redactions)
      redactions.reduce(content) do |result, (pattern, replacement)|
        if replacement.respond_to?(:call)
          result.gsub(pattern) { |match| replacement.call(match) }
        else
          result.gsub(pattern, replacement)
        end
      end
    end

    def line_redactions(line)
      match = parse_sensitive_env_line(line)
      return [] unless match

      build_redactions(match[:key].upcase, match[:value])
    end

    def build_redactions(key, value)
      return [coord_redaction(value)] if COORD_KEYS.include?(key)
      return host_redactions(value) if HOST_KEYS.include?(key)
      return [] if value.length < LOG_REDACTION_MIN_LENGTH

      [[value, mask(value)]]
    end

    def coord_redaction(value)
      [/\b#{Regexp.escape(value)}\d*\b/, method(:coord_mask)]
    end

    def host_redactions(value)
      value.split(',').map(&:strip).filter_map do |part|
        [part, mask(part)] if public_single_hostname?(part)
      end
    end

    def parse_sensitive_env_line(line)
      return nil if line.lstrip.start_with?('#')

      match = line.match(ENV_LINE)
      return nil unless match
      return nil if match[:value].empty? || match[:value].start_with?('${')
      return nil unless line_sensitive?(match[:key], match[:value])

      match
    end

    def line_sensitive?(key, value)
      upper = key.to_s.upcase
      return true if sensitive_key?(upper)
      return !safe_value?(value) if BUCKET_KEYS.include?(upper)
      return public_hostname?(value) if HOST_KEYS.include?(upper)

      false
    end
  end
end
