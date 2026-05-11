# user11

Real-world `compose.yaml` + `.env` from a SOLECTRUS user running an
**all-MQTT pipeline** — every sensor is fed by **evcc** through the
mqtt-collector, with **no senec-collector** in the stack. Forecasts come
from **Solcast** on a two-roof setup (no roof geometry, only site IDs).
The donor exercises the importer's **sign-split MQTT mapping**
expansion: the grid-power and battery-power topics use the
`MEASUREMENT_POSITIVE`/`MEASUREMENT_NEGATIVE` shorthand and round-trip
as separate sensors with sign-filter formulas. Anonymized but otherwise
untouched.

## Imported correctly (round-trip preserves the value)

- **Sign-split MQTT mappings expanded into per-sensor formulas.** First
  fixture exercising
  `MAPPING_x_MEASUREMENT_POSITIVE`/`_NEGATIVE` +
  `MAPPING_x_FIELD_POSITIVE`/`_NEGATIVE`. Donor's `MAPPING_2_TOPIC=evcc/site/grid/power`
  publishes one signed value to two Influx fields
  (`grid_import_power` for the positive half, `grid_export_power` for
  the negative half); same shape for `MAPPING_3_TOPIC=evcc/site/battery/power`
  → `battery_discharging_power` (positive) /
  `battery_charging_power` (negative). HELIOS models one sensor = one
  Influx target, so import expands each split mapping into two
  sensors, each carrying a sign-filter `mqtt_formula`
  (`IF({value} > 0, {value}, 0)` and `IF({value} < 0, -{value}, 0)`).
  The non-matching sign falls back to 0, not NULL, so the series stays
  gap-free for InfluxDB aggregations.
- **MQTT mapping count grows from 8 → 10 on re-export.** Donor packs
  4 sensors into 2 split mappings (grid + battery); HELIOS re-emits
  them as 4 separate `MAPPING_x_*` blocks using the unified
  `MAPPING_x_FORMULA` form. Plus the 6 plain mappings (inverter, house,
  wallbox, wallbox-connected, system_status, battery_soc) carry over
  unchanged. The `mqtt-collector.environment:` block in compose grows
  to reference `MAPPING_0_*` through `MAPPING_9_*` accordingly — every
  exported mapping is wired through (no dead MAPPING entries, unlike
  user10).
- **Pure MQTT pipeline — every sensor `source: mqtt`.** No SENEC
  hardware in the stack; the dashboard reads what evcc writes through
  the mqtt-collector. `inverter_power`, `house_power`,
  `grid_import_power`, `grid_export_power`,
  `battery_charging_power`, `battery_discharging_power`,
  `battery_soc`, `wallbox_power`, `wallbox_car_connected`,
  `system_status` all round-trip with `source: mqtt` plus the
  topic/measurement/field/payload-type tuple from the donor's
  MAPPING_x.
- **`INFLUX_MEASUREMENT_FORECAST=Forecast` (capitalized) preserved.**
  Donor uses the capitalized form (most setups use lowercase
  `forecast`); round-trip keeps `measurement: Forecast` in
  `config.yaml` and re-emits the same casing in `.env`. The
  `INFLUX_SENSOR_INVERTER_POWER_FORECAST=Forecast:watt` reference
  matches verbatim.
- **Solcast multi-roof with `FORECAST_CONFIGURATIONS=2`.** Same shape
  as user10 — `FORECAST_PROVIDER=solcast`,
  `FORECAST_INTERVAL=17280`, `SOLCAST_APIKEY`, plus per-roof site IDs
  round-trip as `forecast: solcast` with `forecast_roofs: 2`,
  `forecast_solcast_id1`, `forecast_solcast_id2`.
- **Solcast multi-roof site precedence — `SOLCAST_0_SITE` wins over
  `SOLCAST_SITE`.** Donor defines three distinct site IDs:
  `SOLCAST_SITE=1111-2222-3333-4444` (legacy single-roof alias),
  `SOLCAST_0_SITE=2222-3333-4444-5555`,
  `SOLCAST_1_SITE=3333-4444-5555-6666`. With
  `FORECAST_CONFIGURATIONS=2` the forecast-collector reads the indexed
  form and ignores `SOLCAST_SITE`; importer (`forecast_extractor.rb`
  `solcast_id1`) honors that — roof 1 imports as `2222-…`, roof 2 as
  `3333-…`. Export rewrites the dead legacy
  `SOLCAST_SITE=1111-…` to `SOLCAST_SITE=2222-…` to match
  `SOLCAST_0_SITE`. Same regression-guard as user10.
- **Watchtower active and image canonicalized.** Donor runs Watchtower
  with image `nickfedor/watchtower` (no tag → implicit `latest`).
  HELIOS imports as a managed service with the explicit
  `nickfedor/watchtower:latest`. Donor's bare `command: --scope solectrus --cleanup`
  collapses into HELIOS's `WATCHTOWER_SCOPE=solectrus` /
  `WATCHTOWER_CLEANUP=true` env-var form (poll interval defaults to
  86400s).
- **Postgres bind-mount already canonical.** Donor mounts
  `${DB_VOLUME_PATH}:/var/lib/postgresql` (no `/data` subpath),
  matching HELIOS's bind-mount layout (ADR-0003) — no rewrite needed
  on export, unlike user10.
- **Power-splitter active in donor compose, preserved on export.**
  Donor wires the service through with all sensor refs intact; export
  keeps it as a managed service. Differs from user10 (where HELIOS
  added power-splitter as new) — here it's already running.

## Equivalent on re-export (no operational impact)

These look like changes in the diff but don't alter what the stack
actually does — HELIOS's defaults match the donor's explicit values,
the value is simply re-spelled, or the var was already dead at runtime.

- **`POWER_SPLITTER_INTERVAL` commented out in `.env` → emitted as
  `3600` on export.** Donor's compose lists `POWER_SPLITTER_INTERVAL`
  in `power-splitter.environment:`, but the `.env` line is commented
  (`# POWER_SPLITTER_INTERVAL=3600`), so the variable was empty at
  runtime and the collector fell back to its built-in default
  (3600s). Re-export emits the explicit default — same calculation
  cadence, no behavior change.
- **`INFLUX_HOST=influxdb` / `INFLUX_PORT=8086` / `INFLUX_SCHEMA=http` /
  `INFLUX_USERNAME=admin`** dropped — HELIOS bakes these into compose
  service-network addressing and hardcodes the InfluxDB admin
  username. Donor used the documented defaults, so re-init against an
  empty volume produces identical credentials. Same as user10.
- **InfluxDB `command:` override dropped.** Donor spelled out the
  default `influxd run --bolt-path … --engine-path … --store disk`;
  these are the InfluxDB 2.x image defaults. Same as user7/user8/user9/user10.
- **`INFLUX_TOKEN=${INFLUX_ADMIN_TOKEN}` on power-splitter rewritten to
  `${INFLUX_TOKEN_READWRITE}`.** HELIOS introduces a dedicated
  readwrite-token alias for the power-splitter; the alias resolves to
  the same admin token in `.env`
  (`INFLUX_TOKEN_READWRITE=my-influx-admin-token`), so the collector
  authenticates with the same credentials.
- **Forecast roof geometry vars emitted empty.** Donor uses Solcast
  (which only needs site IDs) and never sets
  `FORECAST_LATITUDE`/`_LONGITUDE` or
  `FORECAST_x_DECLINATION`/`_AZIMUTH`/`_KWP`. Export emits them as
  empty (`FORECAST_0_DECLINATION=`, etc.) so a future provider switch
  to forecast.solar has the slots ready to fill.
- **Healthcheck timings normalized.** Donor's `interval: 30s` /
  `timeout: 10s|20s` / `start_period: 10s|30s|60s` replaced with
  HELIOS's shorter standard intervals (`interval: 10s` / `timeout: 5s`
  plus a `start_interval: 2s`). Same probes, faster startup feedback.
- **Empty `INFLUX_SENSOR_*` lines dropped.** Donor's `.env` carries
  every sensor slot the upstream template ships, most empty —
  `INFLUX_SENSOR_INVERTER_POWER_1..5=`, all 20
  `INFLUX_SENSOR_CUSTOM_POWER_NN=`, plus
  `INFLUX_SENSOR_CASE_TEMP=`, `INFLUX_SENSOR_SYSTEM_STATUS_OK=`,
  `INFLUX_SENSOR_GRID_EXPORT_LIMIT=`, `_HEATPUMP_*=`,
  `_OUTDOOR_TEMP*=`, `_CAR_BATTERY_SOC=`, `_INVERTER_POWER_FORECAST_CLEARSKY=`.
  Export omits all of them — only the 11 actually-mapped sensors
  remain.
- **Bare-reference vars without `.env` value dropped.** Donor's
  `dashboard.environment:` lists `FRAME_ANCESTORS`, `UI_THEME`,
  `CO2_EMISSION_FACTOR` but `.env` defines none of them (one is
  commented, two are absent). Export omits the unused references.
- **`INFLUX_EXCLUDE_FROM_HOUSE_POWER` dropped — not set in donor `.env`.**
  Donor's compose lists it on dashboard + power-splitter, but `.env`
  has only the commented example
  (`# INFLUX_EXCLUDE_FROM_HOUSE_POWER=HEATPUMP_POWER,WALLBOX_POWER`),
  so no exclusion was active. No sensor in `config.yaml` carries
  `exclude_from_house_power: true`; export omits the bare references.
- **Commented-out alternatives dropped.** `# FRAME_ANCESTORS=…`,
  `# CO2_EMISSION_FACTOR=500`, `# FORECAST_LATITUDE/LONGITUDE/…`, all
  the forecast.solar damping/horizon/multi-plane examples,
  `# FORECAST_SOLAR_APIKEY=abc123`, the `# MAPPING_*` example block —
  removed on re-export (HELIOS only emits active values).
- **Postgres `POSTGRES_DB=solectrus` / dashboard
  `DB_DATABASE=solectrus` added.** HELIOS sets the database name
  explicitly; donor relied on the postgres image default (which is
  also `solectrus` per upstream compose template).
- **Dashboard `REDIS_URL` indirection collapsed to inline literal.**
  Donor uses bare `REDIS_URL` (resolved from `.env` as
  `redis://redis:6379/1`); export inlines the literal in compose
  (`REDIS_URL=redis://redis:6379/1`).
- **InfluxDB UI port stays unpublished.** Donor doesn't expose 8086 to
  the host; HELIOS captures no `influxdb.publish_port` flag, and the
  re-exported `influxdb` service has no `ports:` block. UI is reachable
  only inside the Docker network (the canonical SOLECTRUS default).
- **HELIOS service added.** Self-export — HELIOS always emits its own
  managed service.
- **`name: solectrus` and `networks.default.name` added.** Donor's
  compose has neither (relies on the implicit project name from the
  directory); HELIOS pins both for deterministic service-network
  resolution.
- **Sensor reordering on export.** Donor groups sensors in the
  upstream-template order; export sorts sensors alphabetically inside
  `config.yaml` and renders `.env` in HELIOS's canonical order.
