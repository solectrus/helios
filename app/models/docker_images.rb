# Each entry has `:current` (the recommended default) and optionally
# `:legacy` — images that surface as an "update available" hint in the UI.
# `:current` is either a tag string, or an Array of `{image:, label:}`
# hashes when the user can pick a variant (first entry is the default).
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
      influxdb:2.4.0-alpine
      influxdb:2.3.0-alpine
      influxdb:2.2.0-alpine
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
    current: [
      {
        image: 'ghcr.io/solectrus/solectrus:latest',
        label: {
          de: "Stabil (empfohlen)\n\n" \
              'Geprüfte Releases — wird nur bei neuen Versionen aktualisiert, dafür planbar und zuverlässig.',
          en: "Stable (recommended)\n\n" \
              'Tested releases — only updated when a new version ships, predictable and reliable.',
        }.freeze,
      }.freeze,
      {
        image: 'ghcr.io/solectrus/solectrus:develop',
        label: {
          de: "Entwicklung\n\n" \
              'Wird mehrmals täglich aktualisiert. Neue Features kommen früher an, können aber noch Fehler enthalten.',
          en: "Development\n\n" \
              'Updated multiple times daily. New features arrive earlier, but may still contain bugs.',
        }.freeze,
      }.freeze,
    ].freeze,

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

  INGEST = { current: 'ghcr.io/solectrus/ingest:latest' }.freeze
  HELIOS = { current: 'ghcr.io/solectrus/helios:develop' }.freeze

  WATCHTOWER = {
    current: 'nickfedor/watchtower:latest',

    # The containrrr/watchtower repo is unmaintained — any tag from it is
    # surfaced as an "update available" hint to migrate to the nickfedor fork.
    legacy: %w[
      containrrr/watchtower
    ],
  }.freeze

  SENEC_COLLECTOR = { current: 'ghcr.io/solectrus/senec-collector:latest' }.freeze
  MQTT_COLLECTOR = { current: 'ghcr.io/solectrus/mqtt-collector:latest' }.freeze
  SHELLY_COLLECTOR = { current: 'ghcr.io/solectrus/shelly-collector:latest' }.freeze
  FORECAST_COLLECTOR = { current: 'ghcr.io/solectrus/forecast-collector:latest' }.freeze
  POWER_SPLITTER = { current: 'ghcr.io/solectrus/power-splitter:latest' }.freeze
  TRAEFIK = { current: 'traefik:v3.6' }.freeze

  INFLUXDB_BACKUP = { current: 'ghcr.io/solectrus/influxdb2-s3-backup:latest' }.freeze
  POSTGRESQL_BACKUP = { current: 'ghcr.io/solectrus/postgres-s3-backup:18' }.freeze

  # Compose-service-name → registry-constant lookup. Built once at load time so
  # per-render lookups (one per service row, ~15 rows per dashboard) are O(1)
  # hash hits instead of repeated reflection.
  REGISTRY_BY_SERVICE = constants.each_with_object({}) do |const_name, hash|
    next unless const_get(const_name).is_a?(Hash)

    hash[const_name.to_s.downcase.tr('_', '-')] = const_name
  end.freeze

  # Normalized variant list — single-string `:current` is wrapped as
  # `[{image:}]` so callers don't branch on shape.
  def self.variants(name)
    value = const_get(name).fetch(:current)
    value.is_a?(Array) ? value : [{ image: value }]
  end
  private_class_method :variants

  def self.current(name)
    variants(name).first.fetch(:image)
  end

  # Survey choices for multi-version services, or nil when the registry
  # declares a single-version `:current` — the UI suppresses the chooser.
  def self.choices(name)
    value = const_get(name).fetch(:current)
    value if value.is_a?(Array)
  end

  def self.selectable(name)
    variants(name).pluck(:image)
  end

  # Recommended image tag for a compose-service, or nil if the service has
  # no entry in this registry (e.g. unmanaged / unknown service).
  def self.recommended_for(service_name)
    name = REGISTRY_BY_SERVICE[service_name.to_s]
    current(name) if name
  end

  # Bare-repo legacy entries (e.g. "containrrr/watchtower") are returned
  # untagged; the caller expands them against tags present on the host.
  def self.known_for(service_name)
    name = REGISTRY_BY_SERVICE[service_name.to_s]
    return [] unless name

    data = const_get(name)
    list = Array(data[:current]).map { |entry| entry.is_a?(Hash) ? entry.fetch(:image) : entry }
    list + Array(data[:legacy])
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
    selectable_images = multi_version ? current.pluck(:image) : [current]

    return false if selectable_images.include?(image)
    return true if Array(data[:legacy]).any? { |entry| matches_legacy?(image, entry) }

    multi_version
  end

  def self.matches_legacy?(image, entry)
    return image == entry if entry.include?(':')

    image == entry || image.start_with?("#{entry}:")
  end
  private_class_method :matches_legacy?
end
