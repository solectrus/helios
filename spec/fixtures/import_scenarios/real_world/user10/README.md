# user10

Real-world `compose.yaml` + `.env` from a SOLECTRUS user driving a
**SENEC local adapter** alongside an **evcc-fed wallbox via MQTT**, with
**Solcast** as the forecast provider on a two-roof setup. The donor's
`.env` carries every commented-out alternative the upstream template
ships (forecast.solar damping factors, SENEC cloud credentials, single
vs. multi-roof solcast slots), plus three duplicated/empty
`INFLUX_SENSOR_*` lines and a partially-wired mqtt-collector. Anonymized
but otherwise untouched.

## Imported correctly (round-trip preserves the value)

- **`INFLUX_EXCLUDE_FROM_HOUSE_POWER=WALLBOX_POWER`** — first fixture
  exercising the wallbox exclusion (other fixtures used `HEATPUMP_POWER`).
  Round-trips as `exclude_from_house_power: true` on the `wallbox_power`
  sensor, confirming the dashboard removes wallbox draw from the
  house-power calculation.
- **MQTT-fed wallbox via evcc.** `MAPPING_0_TOPIC=evcc/loadpoints/1/chargePower`
  → `MAPPING_0_MEASUREMENT=pv` / `MAPPING_0_FIELD=wallbox_power` /
  `MAPPING_0_TYPE=integer` round-trips as `wallbox_power.source: mqtt`
  with the topic, measurement, field, and payload type preserved. Only
  this one mapping was actually wired through the donor's
  `mqtt-collector.environment:` block — the other two MAPPING slots
  (see below) never reached the container.
- **Duplicate `INFLUX_SENSOR_SYSTEM_STATUS` — last value wins.** Donor
  defines it twice in `.env`: line 60 as `SENEC:current_state`, then
  line 67 as `pv:system_status`. The env parser keeps the last
  occurrence, so import resolves to `pv:system_status` and round-trips
  as `system_status.source: external` (measurement `pv`, field
  `system_status`) — not the SENEC reading. Same shape applies to the
  duplicated `INFLUX_SENSOR_WALLBOX_CAR_CONNECTED=pv:car_connected`
  (line 58 + line 66, identical values, harmless).
- **Empty sensor mappings dropped.**
  `INFLUX_SENSOR_HEATPUMP_POWER=` and `INFLUX_SENSOR_CAR_BATTERY_SOC=`
  carry empty values; export omits them rather than re-emitting blanks
  (same pattern user1 exercises with `INVERTER_POWER_5=`).
- **`SENEC_INFLUX_MEASUREMENT=SENEC` canonicalized.** Donor uses the
  legacy variable name; export emits the modern
  `INFLUX_MEASUREMENT_SENEC=SENEC`. Same value reaches the
  senec-collector either way — the legacy name is dropped because
  nothing references it.
- **`FORECAST_INFLUX_MEASUREMENT=forecast` canonicalized.** Same legacy
  → modern rename for the forecast measurement (now
  `INFLUX_MEASUREMENT_FORECAST=forecast`); donor's
  `INFLUX_MEASUREMENT=${FORECAST_INFLUX_MEASUREMENT}` indirection on
  `forecast-collector` collapses to the resolved literal.
- **`FORECAST_AZIMUTH=-0` (negative zero) preserved verbatim.**
  Round-trips as the string `"-0"` in `config.yaml` and re-emits as
  `FORECAST_0_AZIMUTH=-0` in `.env` — the minus sign survives the
  YAML/.env round-trip even though it's numerically meaningless.
- **Solcast multi-roof with `FORECAST_CONFIGURATIONS=2`.**
  `FORECAST_PROVIDER=solcast`, `FORECAST_INTERVAL=28800`,
  `SOLCAST_APIKEY`, plus per-roof solcast site IDs round-trip as
  `forecast: solcast` with `forecast_roofs: 2`,
  `forecast_solcast_id1`, `forecast_solcast_id2`.
- **Privacy-redacted geocoords preserved verbatim.** Donor zeros the
  array's location with `FORECAST_LATITUDE=0.00000` /
  `FORECAST_LONGITUDE=0.00000`; round-trip keeps the zero-padded form
  exactly (same shape user9 exercises).
- **Solcast multi-roof site precedence — `SOLCAST_0_SITE` wins over
  `SOLCAST_SITE`.** Donor defines three distinct site IDs:
  `SOLCAST_SITE=1111-2222-3333-4444` (legacy single-roof alias),
  `SOLCAST_0_SITE=2222-3333-4444-5555` (explicit roof 1),
  `SOLCAST_1_SITE=3333-4444-5555-6666` (explicit roof 2). Per upstream
  docs, with `FORECAST_CONFIGURATIONS=2` the forecast-collector reads
  the indexed `SOLCAST_X_SITE` form and ignores `SOLCAST_SITE`. The
  importer (`forecast_extractor.rb` `solcast_id1`) honors that — roof 1
  imports as `2222-…`, roof 2 as `3333-…`. Export re-emits
  `SOLCAST_SITE=2222-…` (rewritten from the donor's `1111-…` to match
  `SOLCAST_0_SITE`), `SOLCAST_0_SITE=2222-…`, `SOLCAST_1_SITE=3333-…`.
  Same site keeps polling for each roof, only the dead legacy alias
  changes value.

## Equivalent on re-export (no operational impact)

These look like changes in the diff but don't alter what the stack
actually does — HELIOS's defaults match the donor's explicit values,
the value is simply re-spelled, or the var was already dead at runtime.

- **`MAPPING_1_*` and `MAPPING_2_*` dropped — already dead in donor
  compose.** Donor's `.env` defines three MQTT mappings — wallbox_power
  (0), wallbox car-connected (1), system_status (2) — but the
  `mqtt-collector.environment:` block only references `MAPPING_0_*`. So
  MAPPING_1/2 never reached the container, no MQTT producer was writing
  to `pv:car_connected` or `pv:system_status`, and those series were
  empty in InfluxDB. Import treats the sensors as `source: external`
  (matching the actual runtime state), and re-export drops the dead
  MAPPING entries — same broken state before and after, no regression.
  If the donor intended these topics to flow, the fix is to add both
  sensors as MQTT-sourced via the HELIOS UI; export will then re-emit
  `MAPPING_1_*` / `MAPPING_2_*` and wire them through compose.
- **`SENEC_IGNORE=wallbox_charge_power` dropped — already dead in donor
  compose.** Same shape: donor defines it in `.env` but
  `senec-collector.environment:` doesn't reference `SENEC_IGNORE`, so
  the senec-collector never received it and was writing
  `wallbox_charge_power` to InfluxDB anyway. Import drops it (absent
  from the senec-collector's resolved env), re-export omits it — the
  collector keeps writing the field, exactly as before. If the user
  actually wants the field filtered, they need to set `senec.ignore`
  via the HELIOS UI; export will then both emit `SENEC_IGNORE` in
  `.env` and add the reference to compose.
- **`INFLUX_HOST=influxdb` / `INFLUX_PORT=8086` / `INFLUX_SCHEMA=http` /
  `INFLUX_USERNAME=admin`** dropped — HELIOS bakes these into compose
  service-network addressing and hardcodes the InfluxDB admin
  username. Donor used the documented defaults, so re-init against an
  empty volume produces identical credentials.
- **InfluxDB `command:` override dropped.** Donor spelled out the
  default `influxd run --bolt-path … --engine-path … --store disk`;
  these are the InfluxDB 2.x image defaults. Same as user7/user8/user9.
- **Forecast.solar params preserved as dead config.** Donor's
  `FORECAST_0_DECLINATION=20` / `_AZIMUTH=-0` / `_KWP=6.92` and the
  matching roof-1 values are forecast.solar-only inputs; the active
  provider is `solcast`, which ignores them. Round-trip keeps them in
  `config.yaml` (under `forecast.forecast_declination1` etc.) and
  re-emits them in `.env` so a future provider switch back to
  `forecast.solar` doesn't lose the geometry.
- **Watchtower commented out → managed default.** Donor's compose has
  the entire `watchtower:` block commented out, meaning the donor
  wasn't running automatic image updates. Export emits
  `watchtower: {}` (managed, default poll interval 86400s, default
  scope `solectrus`, cleanup enabled). The donor effectively gains a
  watchtower service on apply — flag this if the donor explicitly
  wanted manual updates.
- **Power-splitter added.** Donor doesn't run `power-splitter`;
  HELIOS exports it as a managed service with a fixed
  `POWER_SPLITTER_INTERVAL=300` (5-minute cadence, not configurable).
  Idle until the operator configures derived power values.
- **HELIOS service added.** Self-export — HELIOS always emits its own
  managed service.
- **`links:` (legacy) dropped from dashboard and collectors.** Compose
  v2 ignores `links:` for service-network resolution; HELIOS doesn't
  re-emit them on managed services.
- **Healthcheck timings normalized.** Donor's `interval: 30s` /
  `timeout: 10s` / `start_period: 10s|30s|60s` replaced with HELIOS's
  shorter standard intervals (`interval: 10s` / `timeout: 5s` plus a
  `start_interval: 2s`). Same probes, faster startup feedback.
- **Commented-out alternatives dropped.** `# FRAME_ANCESTORS=…`,
  `# SENEC_USERNAME/PASSWORD/SYSTEM_ID`,
  `# FORECAST_PROVIDER=forecast.solar` and its damping/horizon vars,
  `# FORECAST_2_*` / `# FORECAST_3_*`, `# FORECAST_SOLAR_APIKEY=abc123`
  — all removed on re-export (HELIOS only emits active values).
- **Bare-reference vars without `.env` value dropped.** Donor's
  `dashboard.environment:` lists `UI_THEME` and `CO2_EMISSION_FACTOR`
  but `.env` defines neither, so they never had a value. Export omits
  the unused references.
- **Sensor reordering on export.** Donor groups sensors in the
  upstream-template order; export sorts sensors alphabetically inside
  `config.yaml` and renders `.env` in HELIOS's canonical order.
