# Each entry has `:current` (the recommended default) and optionally
# `:legacy` — images that surface as an "update available" hint in the UI.
# `:current` is either a tag string, or an Array of image strings when the
# user can pick a variant (first entry is the default).
#
# Nothing here is ever rewritten automatically: `:current` is only
# consulted when generating defaults for a fresh setup; `:legacy` only
# powers the UI hint. The user decides when to switch.
#
# A legacy entry without a tag matches the repo with any tag (used to flag
# moves away from a deprecated repo, e.g. `containrrr/watchtower`).
#
# Legacy entries originate from the (old) hosting guide, the Configurator, or
# previous HELIOS recommendations:
# https://github.com/solectrus/hosting
# https://github.com/solectrus/configurator

module DockerImages # rubocop:disable Metrics/ModuleLength
  INFLUXDB = {
    current: 'influxdb:2.9-alpine',

    legacy: %w[
      influxdb:2-alpine
      influxdb:2.8-alpine
      influxdb:2.7-alpine
      influxdb:2.6-alpine
      influxdb:2.5-alpine
      influxdb:2.5.1
      influxdb:2.5.0
      influxdb:2.4-alpine
      influxdb:2.4.0-alpine
      influxdb:2.3-alpine
      influxdb:2.3.0-alpine
      influxdb:2.2-alpine
      influxdb:2.2.0-alpine
      influxdb:2.1-alpine
      influxdb:2.1.1-alpine
    ],
  }.freeze

  POSTGRESQL = {
    current: 'postgres:18-alpine',

    # PostgreSQL cannot be upgraded in-place across major versions
    legacy: [],
  }.freeze

  REDIS = {
    current: 'redis:8-alpine',

    legacy: %w[
      redis:7-alpine
      redis:6-alpine
      redis:alpine
    ],
  }.freeze

  DASHBOARD = {
    current: %w[
      ghcr.io/solectrus/solectrus:latest
      ghcr.io/solectrus/solectrus:develop
    ],

    legacy: %w[
      ghcr.io/solectrus/solectrus:1-0-beta
      ghcr.io/solectrus/solectrus:next
      ghcr.io/solectrus/solectrus:power-balance-chart
      ghcr.io/solectrus/solectrus:pr-2836
      ghcr.io/solectrus/solectrus:pr-3160
      ghcr.io/solectrus/solectrus:pr-3349
      ghcr.io/solectrus/solectrus:pr-3432
      ghcr.io/solectrus/solectrus:pr-3533
      ghcr.io/solectrus/solectrus:pr-3747
      ghcr.io/solectrus/solectrus:pr-4151
      ghcr.io/solectrus/solectrus:pr-4195
      ghcr.io/solectrus/solectrus:pr-4403
      ghcr.io/solectrus/solectrus:pr-4588
      ghcr.io/solectrus/solectrus:0
      ghcr.io/solectrus/solectrus:0.13
      ghcr.io/solectrus/solectrus:0.13.0
      ghcr.io/solectrus/solectrus:0.13.1
      ghcr.io/solectrus/solectrus:0.14
      ghcr.io/solectrus/solectrus:0.14.0
      ghcr.io/solectrus/solectrus:0.14.1
      ghcr.io/solectrus/solectrus:0.14.2
      ghcr.io/solectrus/solectrus:0.14.3
      ghcr.io/solectrus/solectrus:0.14.4
      ghcr.io/solectrus/solectrus:0.14.5
      ghcr.io/solectrus/solectrus:0.15
      ghcr.io/solectrus/solectrus:0.15.0
      ghcr.io/solectrus/solectrus:0.15.1
      ghcr.io/solectrus/solectrus:0.16
      ghcr.io/solectrus/solectrus:0.16.0
      ghcr.io/solectrus/solectrus:0.16.1
      ghcr.io/solectrus/solectrus:0.17
      ghcr.io/solectrus/solectrus:0.17.0
      ghcr.io/solectrus/solectrus:0.17.1
      ghcr.io/solectrus/solectrus:0.18
      ghcr.io/solectrus/solectrus:0.18.0
      ghcr.io/solectrus/solectrus:0.18.1
      ghcr.io/solectrus/solectrus:0.18.2
      ghcr.io/solectrus/solectrus:0.18.3
      ghcr.io/solectrus/solectrus:0.19
      ghcr.io/solectrus/solectrus:0.19.0
      ghcr.io/solectrus/solectrus:0.19.1
      ghcr.io/solectrus/solectrus:0.20
      ghcr.io/solectrus/solectrus:0.20.0
      ghcr.io/solectrus/solectrus:0.20.1
      ghcr.io/solectrus/solectrus:0.20.2
      ghcr.io/solectrus/solectrus:0.20.3
      ghcr.io/solectrus/solectrus:1
      ghcr.io/solectrus/solectrus:1.0
      ghcr.io/solectrus/solectrus:1.0.0
      ghcr.io/solectrus/solectrus:1.0.1
      ghcr.io/solectrus/solectrus:1.0.2
      ghcr.io/solectrus/solectrus:1.1
      ghcr.io/solectrus/solectrus:1.1.0
      ghcr.io/solectrus/solectrus:1.1.1
    ],
  }.freeze

  INGEST = {
    current: %w[
      ghcr.io/solectrus/ingest:latest
      ghcr.io/solectrus/ingest:develop
    ],
  }.freeze
  HELIOS = {
    current: %w[
      ghcr.io/solectrus/helios:latest
      ghcr.io/solectrus/helios:develop
    ],
  }.freeze

  WATCHTOWER = {
    current: 'nickfedor/watchtower:latest',

    # The containrrr/watchtower repo is unmaintained — any tag from it is
    # surfaced as an "update available" hint to migrate to the nickfedor fork.
    legacy: %w[
      containrrr/watchtower
    ],
  }.freeze

  SENEC_COLLECTOR = {
    current: %w[
      ghcr.io/solectrus/senec-collector:latest
      ghcr.io/solectrus/senec-collector:develop
    ],
  }.freeze
  MQTT_COLLECTOR = {
    current: %w[
      ghcr.io/solectrus/mqtt-collector:latest
      ghcr.io/solectrus/mqtt-collector:develop
    ],
  }.freeze
  TIBBER_COLLECTOR = {
    current: %w[
      ghcr.io/solectrus/tibber-collector:latest
      ghcr.io/solectrus/tibber-collector:develop
    ],
  }.freeze

  SENEC_CHARGER = {
    current: %w[
      ghcr.io/solectrus/senec-charger:latest
      ghcr.io/solectrus/senec-charger:develop
    ],
  }.freeze
  SHELLY_COLLECTOR = {
    current: %w[
      ghcr.io/solectrus/shelly-collector:latest
      ghcr.io/solectrus/shelly-collector:develop
    ],
  }.freeze
  FORECAST_COLLECTOR = {
    current: %w[
      ghcr.io/solectrus/forecast-collector:latest
      ghcr.io/solectrus/forecast-collector:develop
    ],
  }.freeze
  POWER_SPLITTER = {
    current: %w[
      ghcr.io/solectrus/power-splitter:latest
      ghcr.io/solectrus/power-splitter:develop
    ],
  }.freeze

  TRAEFIK = {
    current: 'traefik:v3.7',

    legacy: %w[
      traefik:v3
      traefik:v3.6
      traefik:v3.5
      traefik:v3.4
      traefik:v3.3
      traefik:v3.2
      traefik:v3.1
      traefik:v3.0
    ],
  }.freeze

  # Compose-service-name → registry-constant lookup. Built once at load time so
  # per-render lookups (one per service row, ~15 rows per dashboard) are O(1)
  # hash hits instead of repeated reflection.
  REGISTRY_BY_SERVICE = constants.each_with_object({}) do |const_name, hash|
    next unless const_get(const_name).is_a?(Hash)

    hash[const_name.to_s.downcase.tr('_', '-')] = const_name
  end.freeze

  # Normalized variant list — a single-string `:current` becomes a one-element
  # array so callers don't branch on shape.
  def self.variants(name)
    Array(const_get(name).fetch(:current))
  end
  private_class_method :variants

  def self.current(name)
    variants(name).first
  end

  # Survey choices for multi-version services, or nil when the registry
  # declares a single-version `:current` — the UI suppresses the chooser.
  def self.choices(name)
    value = const_get(name).fetch(:current)
    value if value.is_a?(Array)
  end

  # Recommended image tag for a compose-service, or nil if the service has
  # no entry in this registry (e.g. unmanaged / unknown service).
  def self.recommended_for(service_name)
    name = REGISTRY_BY_SERVICE[service_name.to_s]
    current(name) if name
  end

  # Major version parsed from a `postgres:<major>…` image tag, or nil when
  # the string is not a recognizable PostgreSQL image.
  def self.postgresql_major(image)
    image.to_s[/postgres:(\d+)/, 1]&.to_i
  end

  # In-container data directory for a given PostgreSQL major. The image's
  # data directory moved between majors: `postgres:17` and older expose
  # `/var/lib/postgresql/data` as the image `VOLUME`, `postgres:18`+ expose
  # the parent `/var/lib/postgresql` (per-major subpath underneath, easing
  # pg_upgrade) — see ADR-0003.
  def self.postgresql_data_path(major)
    major && major <= 17 ? '/var/lib/postgresql/data' : '/var/lib/postgresql'
  end

  # Bare-repo legacy entries (e.g. "containrrr/watchtower") are returned
  # untagged; the caller expands them against tags present on the host.
  def self.known_for(service_name)
    name = REGISTRY_BY_SERVICE[service_name.to_s]
    return [] unless name

    data = const_get(name)
    Array(data[:current]) + Array(data[:legacy])
  end

  # True when the image should surface as "outdated / update available" in
  # the UI. Tagged legacy entries (e.g. `redis:7-alpine`) require an exact
  # match; untagged entries (e.g. `containrrr/watchtower`) match the repo
  # with any tag. For multi-version services, any non-listed image is also
  # treated as legacy — catches imported custom tags (e.g. PR builds).
  def self.legacy?(service_name, image)
    return false if image.nil?

    name = REGISTRY_BY_SERVICE[service_name.to_s]
    return false unless name

    data = const_get(name)
    current = data[:current]
    multi_version = current.is_a?(Array)

    return false if Array(current).include?(image)
    return true if Array(data[:legacy]).any? { |entry| matches_legacy?(image, entry) }

    multi_version
  end

  def self.matches_legacy?(image, entry)
    return image == entry if entry.include?(':')

    image == entry || image.start_with?("#{entry}:")
  end
  private_class_method :matches_legacy?
end
