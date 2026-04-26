# Each image is a hash with `:current` (the recommended default, used as the
# initial value for newly generated configs) and optionally `:legacy` —
# images for which HELIOS surfaces an "update available" hint to the user.
#
# Nothing here is ever rewritten automatically: `:current` is only consulted
# when generating defaults for a fresh setup; `:legacy` only powers the UI
# hint. The user decides when to switch.
#
# A legacy entry without a tag matches the repo with any tag (used to flag
# moves away from a deprecated repo, e.g. `containrrr/watchtower`).
#
# Legacy entries originate from the (old) hosting guide, the Configurator, or
# previous HELIOS recommendations:
# https://github.com/solectrus/hosting
# https://github.com/solectrus/configurator

module DockerImages
  INFLUXDB = {
    current: 'influxdb:2.8-alpine',

    legacy: %w[
      influxdb:2-alpine
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
    current: 'ghcr.io/solectrus/solectrus:latest',

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

  BACKUP_INFLUXDB = { current: 'ghcr.io/solectrus/influxdb2-s3-backup:latest' }.freeze
  BACKUP_POSTGRESQL = { current: 'ghcr.io/solectrus/postgres-s3-backup:18' }.freeze

  def self.current(name)
    const_get(name).fetch(:current)
  end
end
