# user17

Real-world `docker-compose.yml.bak` from a SOLECTRUS user running
**MQTT-only ingest from evcc** with **forecast.solar** forecasts, on a
host that integrates SOLECTRUS into an existing parent compose stack
("`# child compose file for SOLECTRUS`" — line 1). No PV-collector
service: every sensor value flows in over MQTT from `evcc`'s topic
tree. Anonymized but otherwise untouched.

The fixture exercises one quirk no prior fixture covers: **the donor
ships zero `.env` file** — every value the SOLECTRUS stack needs
(secrets, tokens, hostnames, sensor mappings, MQTT topics, forecast
geo, …) lives inline in compose's `environment:` lists. This is a
legitimate, supported compose pattern, but it broke the importer
before this fixture went in: most non-collector extractors only read
`.env`, so a donor with everything inline would lose admin password,
secret key, postgres password, InfluxDB password, InfluxDB tokens,
org, and bucket on import — `Export::Builder#ensure_defaults!` would
then synthesize fresh random secrets, rendering the InfluxDB and
Dashboard inaccessible after re-export. The importer now scopes an
inline `environment:` fallback per canonical service (system→
`dashboard`, postgres→`postgresql`, influx→`influxdb`), so every
inline value round-trips losslessly.

Three smaller first-of-its-kind quirks ride along: `container_name:`
on every service (HELIOS drops these on re-export), a `solectrus-`
prefix on every donor service name (image-prefix matching still
resolves the canonical aliases), and a parent-network reference
(`networks: containerhafen: external: true`) that doesn't survive
the round-trip — HELIOS emits its own `solectrus_default` bridge.

## Anonymization

The donor's compose was a "child compose file" — `containerhafen` is
declared in their parent compose, not this file. The fixture adds the
two-line `networks: containerhafen: external: true` declaration at
the bottom so `docker compose config` can parse the file standalone;
without it, the importer aborts on `service refers to undefined
network`. No `.env.bak` is present — the donor genuinely ships none,
and the bootstrap rake task plus `StackReader` were taught to tolerate
its absence as part of this fixture going in.

## Imported correctly (round-trip preserves the value)

- **All inline secrets and tokens survive** — donor inlines
  `ADMIN_PASSWORD=my-admin-password`, `SECRET_KEY_BASE=my-secret-key-base`,
  `DB_PASSWORD=my-db-password` (postgresql side: `POSTGRES_PASSWORD=my-db-password`),
  `DOCKER_INFLUXDB_INIT_PASSWORD=my-influx-password`, and a single
  `INFLUX_TOKEN=my-influx-admin-token` used by Dashboard, mqtt-collector,
  and forecast-collector alike. The importer's per-service inline
  fallback ([system→dashboard, postgres→postgresql, influx→influxdb])
  captures every one; HELIOS re-emits them into `.env` byte-identical
  rather than auto-generating fresh values. First fixture where
  `dashboard_env[KEY]` (resolved compose env) is the only source of
  truth for `admin_password` / `secret_key_base`.
- **Single `INFLUX_TOKEN=my-influx-admin-token` expands to all four token
  roles.** Donor uses one token literally everywhere (Dashboard,
  mqtt-collector, forecast-collector, plus InfluxDB's
  `DOCKER_INFLUXDB_INIT_ADMIN_TOKEN`). HELIOS captures it via
  `inline: 'influxdb'` on each `TOKEN_FALLBACKS` chain and re-emits
  `INFLUX_ADMIN_TOKEN` / `INFLUX_TOKEN_READWRITE` /
  `INFLUX_TOKEN_WRITE` / `INFLUX_TOKEN_READ`, all four set to
  `my-influx-admin-token`. Similar shape to user13/15/16's single-token
  shortcut but the first fixture where the token never appears in
  `.env` at all.
- **`INFLUX_ORG=solectrus`, `INFLUX_BUCKET=my-solectrus-bucket` from
  inline preserved.** Donor declares both on every service that
  touches InfluxDB. HELIOS reads them through the influxdb-scoped
  inline fallback and re-emits them in `.env`. `org=solectrus`
  happens to match the HELIOS default; `bucket=my-solectrus-bucket`
  is custom and is the first fixture where a non-default bucket name
  arrives without any `.env` file.
- **Legacy `MQTT_TOPIC_*` mapping for evcc topics, with
  `MQTT_FLIP_BAT_POWER=true` set as inline literal.** Donor uses the
  pre-MAPPING-style env vars: `MQTT_TOPIC_HOUSE_POW=evcc/site/homePower`,
  `MQTT_TOPIC_GRID_POW=evcc/site/grid/power`,
  `MQTT_TOPIC_BAT_FUEL_CHARGE=evcc/site/battery/soc`,
  `MQTT_TOPIC_BAT_POWER=evcc/site/battery/power`,
  `MQTT_TOPIC_INVERTER_POWER=evcc/site/pvPower`,
  `MQTT_TOPIC_WALLBOX_CHARGE_POWER=evcc/loadpoints/1/chargePower`.
  HELIOS expands them to canonical `MAPPING_N_*` entries. The
  `MQTT_FLIP_BAT_POWER=true` flips the bat_power_plus/minus sign
  split, so the `evcc/site/battery/power` topic produces
  `battery_charging_power` from negative values (charging is
  reported negative by evcc) and `battery_discharging_power` from
  positive — visible in the resulting `mqtt_formula` formulas
  (`IF({value} < 0, -{value}, 0)` vs `IF({value} > 0, {value}, 0)`).
  Differs from user1/no_sensor_configuration: those two pass
  `MQTT_FLIP_BAT_POWER` as a bare env-reference (no inline value);
  user17 is the first fixture with the literal `MQTT_FLIP_*=true`
  declared directly on the service.
- **Custom `INFLUX_MEASUREMENT_PV=my-pv-measurement`.** Donor uses
  a non-default measurement name (HELIOS default is `SENEC`); every
  inline `INFLUX_SENSOR_*=my-pv-measurement:<field>` plus the
  `INFLUX_MEASUREMENT=my-pv-measurement` writer var picks it up via
  `service_env`. Every sensor ends up with `measurement:
  my-pv-measurement` in `config.yaml`.
- **`docker-compose.yml.bak` filename variant — fifth in this
  slot.** Same `Compose::FILENAMES` slot as user3/4/12/16; the
  other three slots are covered by user1/2/5/7..11/14/15
  (`compose.yaml`), user6/10 (`compose.yml`), and user13
  (`docker-compose.yaml`).
- **External Docker named volumes for app data
  (`solectrus-influxdb`, `solectrus-db`, `solectrus-redis`, all
  `external: true`).** First fixture where the donor uses externally
  managed named volumes (rather than bind mounts) for all three
  stateful services. Each survives in `_unmanaged.volumes` and is
  re-emitted in the exported `compose.yaml` with the same
  `external: true` flag. `volume_path: solectrus-influxdb` /
  `solectrus-redis` / `solectrus-db` end up in `config.yaml` as plain
  string identifiers (no path semantics).

## Equivalent on re-export (no operational impact)

- **`container_name:` directives dropped from every service.**
  Donor sets `container_name: solectrus-app`, `solectrus-db`,
  `solectrus-influxdb`, `solectrus-redis`, `solectrus-mqttcollector`,
  `solectrus-forecast-collector` — letting them appear under those
  fixed names in `docker ps`. HELIOS emits services under canonical
  short names (`dashboard`, `postgresql`, `influxdb`, `redis`,
  `mqtt-collector`, `forecast-collector`) without `container_name`,
  so docker auto-names the containers `solectrus-dashboard-1` etc.
  Operationally equivalent — DNS within the compose network keys on
  service name, not container name. First fixture exercising this
  drop.
- **Donor's `solectrus-` service-name prefix canonicalized.**
  `solectrus-app` resolves to `dashboard` via
  `SERVICE_IMAGE_PREFIXES['dashboard']`; `solectrus-db` to
  `postgresql`; `solectrus-mqttcollector` to `mqtt-collector`; etc.
  Image-prefix matching handles every one; no donor service is left
  unresolved.
- **`containerhafen` external-network reference dropped.**
  HELIOS emits a single `networks: default: name:
  solectrus_default` block instead. Operationally the donor will
  need to re-attach their parent-compose network manually after
  re-export, or accept that SOLECTRUS now runs in its own bridge
  network. The fixture does not preserve this — `config.yaml` has no
  network-overlay configuration for this case.
- **`INFLUX_HOST=solectrus-influxdb` / `INFLUX_SCHEMA=http` /
  `INFLUX_PORT=8086` dropped from collectors.** Donor sets these
  inline on every service that talks to InfluxDB. HELIOS bakes the
  in-network address (`http://influxdb:8086`) into compose's
  service-discovery layer and drops the variables from the
  collector env blocks.
- **InfluxDB explicit `command: influxd run --bolt-path ...
  --engine-path ... --store disk` override dropped.** Same
  explicit-defaults override as user7-16 — donor pins the same
  paths the image's default entrypoint would use anyway.
- **`DB_USER=postgres` / `INFLUX_USERNAME=admin` dropped from
  `.env`.** Donor inlines `DB_USER=postgres` (Dashboard) and the
  InfluxDB init uses `admin` implicitly. HELIOS bakes both as
  hardcoded canonical defaults on export; the explicit donor
  values match HELIOS's choice, only the redundant variable
  presence changes.
- **`POSTGRES_DB=solectrus` / `DB_DATABASE=solectrus` added.**
  Donor relied on the postgres image's `solectrus` default for the
  DB name; HELIOS sets it explicitly. Same shape as user12-16.
- **Power-splitter service added.** Donor compose has no
  `power-splitter` (MQTT-only setup with no native PV collector).
  HELIOS adds it as a managed service with
  `POWER_SPLITTER_INTERVAL=3600` (default) and wires it with
  `INFLUX_TOKEN_READWRITE=my-influx-admin-token` (synthesized from the
  donor's single-token simplification). Same auto-add as
  user10/12/16.
- **Watchtower service added with HELIOS defaults
  (`nickfedor/watchtower:latest`, `WATCHTOWER_POLL_INTERVAL=86400`,
  `WATCHTOWER_SCOPE=solectrus`, `WATCHTOWER_CLEANUP=true`).**
  Donor's compose has no Watchtower. HELIOS adds the canonical
  managed service and tags every other service with the
  `com.centurylinklabs.watchtower.scope=solectrus` label.
- **HELIOS service added.** Self-export, test-env only.
- **Donor `# - MQTT_TOPIC_BAT_CHARGE_CURRENT` (and six other
  commented-out `MQTT_TOPIC_*` lines) dropped.** YAML parsing
  ignores them at import; HELIOS doesn't re-emit them. Comments
  inside `compose.yaml` are not preserved (CLAUDE.md
  "Project-Specific Rules").
- **Restart policy normalized to `unless-stopped` on every
  service.** Donor already uses `unless-stopped` on every service,
  so this is a no-op renaming.
- **`logging.driver: json-file` added uniformly.** Donor doesn't
  set a logging driver; HELIOS normalizes every service to the
  same explicit `json-file` driver with rotation limits
  (10m/3 files).
- **Healthcheck timings normalized.** Donor's per-service
  intervals (`10s` / `20s` / `30s`) replaced with HELIOS's
  canonical `interval: 10s` / `timeout: 5s` / `start_interval: 2s`.
- **`INFLUX_POLL_INTERVAL=5` preserved as a `dashboard:` setting**
  rather than a top-level `.env` var. Donor's inline value
  (`INFLUX_POLL_INTERVAL=5`) ends up under
  `config.yaml.dashboard.influx_poll_interval: '5'` and re-emits
  back into `.env` identically.
- **`INFLUX_MEASUREMENT_FORECAST=Forecast` collapsed.** Donor sets
  it both as `- INFLUX_MEASUREMENT_FORECAST=Forecast` on the
  Dashboard and `- INFLUX_MEASUREMENT=Forecast` on the
  forecast-collector. HELIOS keeps the canonical
  `INFLUX_MEASUREMENT_FORECAST=Forecast` in `.env` and re-emits a
  bare `INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_FORECAST}`
  indirection on the forecast-collector.
- **`FORECAST_CONFIGURATIONS=1` (single-roof) dropped from `.env`.**
  Donor declares `FORECAST_CONFIGURATIONS=1` explicitly. HELIOS
  treats `forecast_roofs: '1'` as the default and skips the
  redundant top-level var.
- **forecast-collector's `INFLUX_MEASUREMENT_FORECAST=Forecast`
  duplicated env entry collapsed.** Donor sets both `INFLUX_MEASUREMENT=Forecast`
  and `INFLUX_MEASUREMENT_FORECAST=Forecast` inline on
  forecast-collector. HELIOS keeps a single canonical reference
  through `${INFLUX_MEASUREMENT_FORECAST}` indirection.
- **`name: solectrus` and `networks.default.name: solectrus_default`
  added.** Donor has neither.
- **Sensor reordering on export.** Donor groups sensors loosely;
  export sorts sensors alphabetically in `config.yaml` and renders
  `.env` in HELIOS's canonical block order.
