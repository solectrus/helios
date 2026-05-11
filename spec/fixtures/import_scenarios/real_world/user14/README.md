# user14

Real-world `compose.yaml` + `.env` from a SOLECTRUS user running a
**local-adapter SENEC V3 (two MPPTs) plus two external Fronius
inverters** on a duplex (main apartment + granny flat) with a four-roof
PV installation. The donor's stack also wires `power-splitter`,
`watchtower`, a `forecast-collector` (forecast.solar, four planes), an
`mqtt-collector`, and a single calculated heatpump-power sensor. The
fixture exercises three new shapes at once: a **bare-name
`SENEC_ADAPTER`** entry in `.env` (no `=`, no value), a **duplicate
`INFLUX_SENSOR_HEATPUMP_HEATING_POWER=`** declaration, and **two orphan
collector services** (mqtt-collector and forecast-collector) whose
broker / plane config is captured in `config.yaml` but whose service
definition is dropped on re-export because nothing consumes them.
Anonymized but otherwise untouched.

## Imported correctly (round-trip preserves the value)

- **Bare-name `SENEC_ADAPTER` in `.env.bak` (no `=`).** Donor's `.env`
  line 257 is literally `SENEC_ADAPTER` with no `=` and no value — a
  malformed-but-tolerated dotenv entry. The senec-collector compose env
  block also passes it through bare (`- SENEC_ADAPTER`). `SensorsExtractor`/
  `SenecExtractor` parses the missing value as `nil` and falls back to
  `senec_env['SENEC_ADAPTER'] || 'local'`, yielding `senec.adapter: local`
  in `config.yaml` and `SENEC_ADAPTER=local` on re-export. First fixture
  exercising the bare-name `.env` shape (user13 used `# `-prefixed
  cloud-credential vars; this is the looser variant where the donor
  forgot the `=` entirely).
- **`SENEC_HOST=192.168.1.33` inlined in compose, not in `.env`.** Donor
  hardcodes the IP directly in the senec-collector `environment:` block
  rather than passing it through `.env`. `senec.host: 192.168.1.33`
  captures the inline literal; re-export promotes it to the canonical
  `.env` slot (`SENEC_HOST=192.168.1.33`) and the compose entry becomes
  a bare passthrough.
- **Duplicate `INFLUX_SENSOR_HEATPUMP_HEATING_POWER=` in `.env.bak`.**
  Lines 70 and 71 declare the same key twice (both empty). `Env.read`
  hands the last-write-wins value to the importer, which then drops it
  via the same `well_formed_mapping?` empty-value filter as user13's
  template slots. First fixture with a duplicate-key `.env` line —
  confirms dotenv parsing tolerates the redundancy and the importer
  doesn't double-count or error.
- **MQTT broker captured without an mqtt-collector service on
  re-export.** Donor's compose has a full `mqtt-collector` service with
  inline `MQTT_HOST=192.168.1.39`, `MQTT_PORT=1883`, `MQTT_SSL=false`,
  `MQTT_USERNAME=XXXXX`, `MQTT_PASSWORD=XXXXX` (and a hardcoded
  `INFLUX_TOKEN=XXXXX` against `INFLUX_BUCKET=solectrus`), but **zero**
  sensors are sourced from MQTT. `MqttExtractor#broker_data` populates
  `config.yaml.mqtt` (host/port/ssl/username/password) so the broker
  credentials survive; on export `Services::MqttCollector.enabled?`
  returns false (`mqtt_required? == false`, `mqtt_topics.empty?`), so
  the service is omitted from `compose.yaml`. First fixture with an
  **orphan mqtt-collector** — broker config preserved on the config
  side, dead service removed on the compose side.
- **forecast-collector orphan with full four-plane config.** Donor
  runs a forecast-collector against forecast.solar with
  `FORECAST_CONFIGURATIONS=4` and per-plane overrides
  (`FORECAST_0..3_DECLINATION/_AZIMUTH/_KWP`) — but **no sensor is
  sourced from `forecast`** (`INFLUX_SENSOR_INVERTER_POWER_FORECAST=`
  is empty). `ForecastExtractor` captures the planes verbatim into
  `config.yaml.forecast` (`forecast_roofs: '4'`, 12 plane fields,
  `forecast: forecast.solar`, `INFLUX_MEASUREMENT_FORECAST=Forecast`);
  on export `Services::ForecastCollector.enabled?` returns false
  (`forecast_required? == false`), so the service is omitted. Same
  orphan-service shape as mqtt above but on a different collector.
  First fixture exercising it.
- **Mixed-source inverter slots: SENEC MPPTs + two external Fronius.**
  Donor maps
  `INFLUX_SENSOR_INVERTER_POWER_1=SENEC:mpp1_power`,
  `_2=SENEC:mpp2_power`,
  `_3=FRONIUS_inverter_1:power`,
  `_4=FRONIUS_inverter_2:power`. Two slots resolve to
  `source: senec` (sensor lives on the SENEC measurement); two slots
  resolve to `source: external` with `measurement: FRONIUS_inverter_{1,2}`
  / `field: power`. First fixture with a **split inverter array**
  (battery system delivers the first two strings, separate Fronius
  units the next two) — the measurement-divergence heuristic correctly
  keeps both groups as inverters rather than flagging the split as
  custom.
- **`FORECAST_CONFIGURATIONS=4` with all four planes populated.** Donor
  runs a four-roof setup: 90°/4.97 kWp, -90°/4.615 kWp, -90°/5.53 kWp,
  -90°/2.37 kWp (all 15°-40° declination). All twelve plane fields
  round-trip as strings (`forecast_azimuth1..4`, `_declination1..4`,
  `_kwp1..4`) plus `forecast_roofs: '4'`. Highest plane count in the
  real-world fixtures so far.
- **Two custom power sensors as duplex split.** Donor uses
  `INFLUX_SENSOR_CUSTOM_POWER_01=MAIN_APARTMENT_POWER_CALCULATED:power`
  and `_02=GRANNY_FLAT_POWER_CALCULATED:power` to model a two-unit
  dwelling. Both round-trip as `source: external` with the calculated
  measurement names intact. Custom slots 03..20 are template-empty and
  drop (same path as user13).
- **`SOLCAST_SITE=my-solcast-site` declared but ignored.** Donor leaves
  the alternate-provider value live in `.env.bak` (`SOLCAST_APIKEY` is
  commented out, the site is not). `ForecastExtractor#provider_data`
  only reads SOLCAST_* when `FORECAST_PROVIDER=solcast`; since the
  donor runs `forecast.solar`, the site is dropped silently. First
  fixture exercising the "tried both providers, kept settings around"
  shape.
- **Heatpump power without companion heatpump sensors.** Donor has
  `INFLUX_SENSOR_HEATPUMP_POWER=HEATPUMP_POWER_CALCULATED:power` (a
  power-splitter-calculated value, `source: external`) but every other
  heatpump slot (`_HEATING_POWER`, `_TANK_TEMP`, `_TANK_TEMP_SETPOINT`,
  `_HEATPUMP_STATUS`) is empty and drops. Confirms a single heatpump-
  power sensor survives without the full device suite.
- **Power-splitter wired via `INFLUX_TOKEN=${INFLUX_ADMIN_TOKEN}`.**
  Same admin-token shortcut as user13. HELIOS normalizes to
  `INFLUX_TOKEN=${INFLUX_TOKEN_READWRITE}` and synthesizes
  `INFLUX_TOKEN_READWRITE=my-influx-admin-token` in `.env`.
- **`INFLUX_TOKEN_WRITE` / `INFLUX_TOKEN_READ` / `INFLUX_ADMIN_TOKEN`
  all distinct.** Donor uses three separate values
  (`my-influx-write-token`, `my-influx-read-token`,
  `my-influx-admin-token`) — opposite of user13's single-value
  simplification. Round-trip keeps all three distinct and adds
  `INFLUX_TOKEN_READWRITE=my-influx-admin-token` (admin-token fallback,
  since power-splitter wired via `INFLUX_ADMIN_TOKEN`).
- **Trailing whitespace on a compose env line.** `compose.yaml.bak`
  line 45 is `- INFLUX_SENSOR_BATTERY_SOC=SENEC:bat_fuel_charge     `
  with five trailing spaces. YAML parsing tolerates it; the importer
  treats the value as `SENEC:bat_fuel_charge` (whitespace-stripped),
  and re-export emits the clean form. Low-stakes detail, but
  documents that donor-supplied trailing whitespace doesn't leak
  through.
- **`INSTALLATION_DATE=2021-01-01` preserved as `'2021-01-01'`.**
  Five-year-old install, same quoted-ISO-string shape as user11/12/13.
- **`APP_HOST=192.168.1.39` (raw IPv4) preserved.** Donor reaches
  dashboard by IP; the same IP appears as `MQTT_HOST` inline on
  mqtt-collector, suggesting broker and dashboard share a host.
  Importer doesn't try to deduplicate or rewrite.
- **InfluxDB UI port `8086:8086` preserved via `publish_port`.**
  Donor publishes the InfluxDB UI on host port 8086. Import captures
  `influxdb.publish_port: true` so re-export keeps the `ports:`
  block on the `influxdb` service. HELIOS's default is to leave the
  UI port unpublished (canonical SOLECTRUS shape); the flag flips
  that default back on for donors who rely on direct UI access.
- **Volume paths preserved.** Canonical ADR-0003 layout
  (`./influxdb`, `./postgresql`, `./redis`), unchanged on re-export.
- **Modern image baseline preserved.** `postgres:18-alpine`,
  `redis:8-alpine`, `influxdb:2-alpine`,
  `ghcr.io/solectrus/solectrus:latest` — same baseline as user13.
- **`INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_SENEC}` indirection
  collapsed.** Donor uses the older template style; HELIOS rewrites the
  senec-collector entry to a direct `INFLUX_MEASUREMENT_SENEC`
  passthrough (same canonicalization as user12/13). Measurement string
  `SENEC` survives unchanged.
- **Watchtower `nickfedor/watchtower` (no tag) → `:latest`, command
  → env vars.** Donor's bare `command: --scope solectrus --cleanup`
  splits to `WATCHTOWER_SCOPE=solectrus` / `WATCHTOWER_CLEANUP=true`,
  plus default `WATCHTOWER_POLL_INTERVAL=86400`. Same path as
  user6/user12/user13.

## Equivalent on re-export (no operational impact)

- **`forecast-collector` service block dropped.** Donor's full
  forecast-collector definition (image, env, depends_on, healthcheck,
  logging, labels) is removed because no HELIOS sensor consumes its
  output. The `.env` keys (`FORECAST_*`, `INFLUX_MEASUREMENT_FORECAST`)
  are also dropped — only `config.yaml.forecast` carries the values
  forward, ready for a future `inverter_power_forecast` sensor to
  re-enable the service.
- **`mqtt-collector` service block dropped.** Donor's mqtt-collector
  (with anonymized `MQTT_USERNAME=XXXXX` / `MQTT_PASSWORD=XXXXX` /
  `INFLUX_TOKEN=XXXXX`) is removed because no HELIOS sensor reads from
  MQTT. Broker credentials survive only in `config.yaml.mqtt`.
- **`SENEC_TOTP_URI` / `SENEC_USERNAME` / `SENEC_PASSWORD` env
  passthroughs dropped from senec-collector.** Donor's compose lists
  them as bare passthroughs even though `.env.bak` never sets them.
  HELIOS strips the dead references (same shape as user13's commented-
  out cloud creds, just less aggressive on the donor's part).
- **`SENEC_SCHEMA=https` / `SENEC_LANGUAGE=de` / `SENEC_INTERVAL=5`
  emitted on re-export from defaults.** Donor's `.env.bak` defines
  none of them; compose passes them through bare. HELIOS fills in the
  documented defaults explicitly so the collector behaviour is
  reproducible without relying on the senec-collector image's own
  fallbacks.
- **`links: - influxdb` blocks dropped from senec-collector,
  mqtt-collector, and (implicitly) power-splitter.** Legacy compose
  feature; bridge-network service discovery makes them no-ops. Same as
  user12/13.
- **InfluxDB `command: influxd run --bolt-path ... --engine-path ...
  --store disk` dropped.** Donor's explicit-defaults override removed
  (same as user7-13).
- **`INFLUX_HOST=influxdb` / `INFLUX_PORT=8086` / `INFLUX_SCHEMA=http`
  / `INFLUX_USERNAME=admin` dropped from `.env`.** Same as user10-13:
  baked into compose service-network defaults.
- **Empty `FRAME_ANCESTORS` / `UI_THEME` / `CO2_EMISSION_FACTOR`
  passthroughs dropped from dashboard env.** Donor lists them as bare
  references in compose but never sets values in `.env` (the
  template-comments stay `# `-prefixed). HELIOS drops the dead env
  lines (same as user13).
- **`REDIS_URL=redis://redis:6379/1` inlined.** Donor wires it through
  `.env` + `- REDIS_URL` passthrough; HELIOS inlines the literal in
  dashboard and power-splitter env blocks and drops the `.env` entry.
  Same as user12/13.
- **`INFLUX_SCHEMA` / `INFLUX_PORT` dropped from collector env.**
  Donor passes them through (`- INFLUX_SCHEMA`, `- INFLUX_PORT`);
  HELIOS bakes the connection into the in-network default
  `http://influxdb:8086`. Same as user13.
- **`POWER_SPLITTER_INTERVAL=3600` emitted (donor had it commented).**
  Donor's `.env.bak` leaves `# POWER_SPLITTER_INTERVAL=3600` commented;
  at runtime the collector falls back to its built-in default (also
  `3600`). HELIOS emits the documented default explicitly.
- **`POSTGRES_DB=solectrus` / `DB_DATABASE=solectrus` added.** Donor
  relied on the postgres image default (also `solectrus`); HELIOS sets
  the name explicitly. Same as user12/13.
- **`POSTGRES_PASSWORD` plain passthrough added to power-splitter
  env.** Donor only wires `DB_PASSWORD=${POSTGRES_PASSWORD}`; HELIOS
  adds the raw `POSTGRES_PASSWORD` passthrough too. Same as user13.
- **`name: solectrus` and `networks.default.name: solectrus_default`
  added.** Donor has neither.
- **HELIOS service added.** Self-export.
- **Healthcheck timings normalized.** Donor's per-service intervals
  (`30s` / `10s`) and timeouts (`10s` / `20s`) replaced with HELIOS's
  standard `interval: 10s` / `timeout: 5s` / `start_interval: 2s`.
  Same probes, faster startup feedback.
- **Sensor reordering on export.** Donor follows the upstream
  template's loose grouping; export sorts sensors alphabetically in
  `config.yaml` and renders `.env` in HELIOS's canonical block order.
- **Trailing whitespace stripped on
  `INFLUX_SENSOR_BATTERY_SOC=SENEC:bat_fuel_charge`.** Donor's compose
  line 45 has five trailing spaces after the value; round-trip emits
  the clean form.
