# user9

Real-world `compose.yaml` + `.env` from a SOLECTRUS user driving a
**three-MPPT SENEC** system through the **cloud adapter** (TOTP MFA), with a
**Daikin heat pump monitored via Shelly**, a **pvnode forecast**, and two
extra SOLECTRUS services HELIOS does not natively manage —
`senec-charger` and `tibber-collector`. Six `custom_power_*` slots are wired
to plain external measurements (no per-Shelly mapping), and `power-splitter`
runs at the documented minimum interval. Anonymized but otherwise untouched.

## Imported correctly (round-trip preserves the value)

- **Two unmanaged SOLECTRUS services preserved.** First fixture exercising
  `senec-charger` and `tibber-collector` — both are real SOLECTRUS images
  (`ghcr.io/solectrus/senec-charger:develop`,
  `ghcr.io/solectrus/tibber-collector:develop`) for which HELIOS has no
  managed exporter. They land under `_unmanaged.services.*` with their
  `depends_on`, `links`, `logging`, and `restart` blocks intact, and their
  `INFLUX_TOKEN=${INFLUX_TOKEN_READ}` / `${INFLUX_TOKEN_WRITE}` indirections
  re-emitted verbatim — donor's choice of which token feeds which collector
  is preserved.
- **Per-service env_file vars captured as `env_values`.** `senec-charger`
  and `tibber-collector` use `env_file: .env`, so their effective env is the
  full union of the donor's `.env`. HELIOS dry-runs the canonical export
  during import to find out which vars it will emit itself, then records
  only the rest under each service's `env_values` — unrecognized donor vars
  (`CHARGER_DRY_RUN`, `CHARGER_INTERVAL`, `INFLUX_MEASUREMENT_PRICES`,
  `INFLUX_MEASUREMENT_SHELLY_HEATPUMP`, `TIBBER_TOKEN`) and managed vars
  HELIOS won't re-emit in the donor's
  configuration (`SENEC_HOST` / `SCHEMA` / `LANGUAGE` because adapter is
  cloud, `FORECAST_CONFIGURATIONS=1` because single-roof drops the suffix,
  `PVNODE_PAID=false` because it matches the image default). Vars HELIOS
  already emits canonically (`INFLUX_BUCKET`, `SENEC_USERNAME`, …) stay
  out, so `config.yaml` doesn't duplicate them.
- **SENEC cloud adapter with TOTP MFA.** `SENEC_ADAPTER=cloud` plus
  `SENEC_USERNAME` / `SENEC_PASSWORD` / `SENEC_TOTP_URI` / `SENEC_SYSTEM_ID`
  round-trip as `senec.adapter: cloud` with the four cloud credentials.
  Local-adapter siblings (`SENEC_HOST=senec.fritz.box`, `SENEC_SCHEMA=https`,
  `SENEC_LANGUAGE=de`) are *not* dead vars here — `senec-charger` lists
  them as bare references in its `environment:` block and would crash at
  startup without them. They survive under `senec-charger.env_values` and
  reappear in `.env` even though the canonical SENEC section (cloud mode)
  no longer emits them.
- **Three-MPPT SENEC inverter.**
  `INFLUX_SENSOR_INVERTER_POWER_1/2/3=SENEC:mpp1_power/mpp2_power/mpp3_power`
  round-trip as `inverter_power_1/2/3` with `source: senec` — same
  three-string shape as user8 but here on the canonical SENEC measurement
  (not a Home Assistant bridge).
- **Heat pump monitored via Shelly with measurement indirection.** Donor
  defines `INFLUX_MEASUREMENT_SHELLY_HEATPUMP=Consumer` in `.env` and
  bridges with `INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_SHELLY_HEATPUMP}` on
  the shelly-collector service. Round-trip resolves to the literal value and
  emits `INFLUX_MEASUREMENT=Consumer` directly — same indirection-collapse
  pattern user2/user8 exercised on the forecast measurement, here applied to
  Shelly. The matching sensor `heatpump_power=Consumer:power` round-trips
  as `source: shelly` with `shelly_host: shelly-heatpump.fritz.box`.
- **`SENEC_INFLUX_MEASUREMENT` indirection collapsed to canonical form.**
  Donor sets `SENEC_INFLUX_MEASUREMENT=SENEC` and bridges with
  `INFLUX_MEASUREMENT=${SENEC_INFLUX_MEASUREMENT}` on `senec-collector`.
  Round-trip emits canonical `INFLUX_MEASUREMENT_SENEC=SENEC` and the
  collector picks it up directly. The legacy var name is a known
  Online-Configurator alias (2024-03..10) of `INFLUX_MEASUREMENT_SENEC`, so
  it is dropped rather than carried forward in the unmanaged `senec-charger`
  env_values block.
- **Three distinct InfluxDB tokens preserved.** `INFLUX_TOKEN_READ`
  (dashboard, senec-charger), `INFLUX_TOKEN_WRITE` (collectors,
  tibber-collector) and `INFLUX_ADMIN_TOKEN` (InfluxDB init,
  power-splitter) all carry **different** values; round-trip preserves all
  three plus a new `INFLUX_TOKEN_READWRITE=${INFLUX_ADMIN_TOKEN}` alias
  that `power-splitter` now references. No privilege escalation — the
  dashboard keeps its read-only token, unlike user5/user8 where distinct
  tokens collapsed into one.
- **`INFLUX_EXCLUDE_FROM_HOUSE_POWER=HEATPUMP_POWER` preserved.** Same
  shape user1/user8 exercise — heat-pump consumption stays out of the
  house-power calculation, applied as `exclude_from_house_power: true` on
  the `heatpump_power` sensor.
- **Six external `custom_power_*` slots with CamelCase measurements.**
  `Washer:power`, `Fridge:power`, `KabelFritz:power`, `Synology:power`,
  `iMac:power`, `Dishwasher:power` — all `source: external`, no Shelly or
  MQTT pipeline. The mixed-case measurement names (e.g. `KabelFritz`,
  `iMac`) and the `name:` field (defaulted to the measurement) round-trip
  unchanged.
- **External `outdoor_temp` and `heatpump_heating_power`.**
  `outdoor:temperature` and `heatpump:heating_power` round-trip as
  `source: external` sensors with their measurement/field pair preserved.
  Donor uses `heatpump_heating_power` for actual thermal output, distinct
  from the electric input on `heatpump_power`.
- **pvnode forecast with single roof and extra params.**
  `FORECAST_PROVIDER=pvnode`, `FORECAST_CONFIGURATIONS=1`,
  `FORECAST_0_DECLINATION=28`, `FORECAST_0_AZIMUTH=209`,
  `FORECAST_0_KWP=9.24`, `PVNODE_APIKEY`,
  `PVNODE_EXTRA_PARAMS=panel_age_years=4` round-trip as `forecast: pvnode`
  with all parameters preserved. `inverter_power_forecast`,
  `inverter_power_forecast_clearsky`, and `outdoor_temp_forecast` all map to
  the forecast source.
- **Single-roof forecast collapsed to un-numbered form.** Because
  `FORECAST_CONFIGURATIONS=1`, round-trip drops the `_0_` suffix —
  `FORECAST_0_AZIMUTH=209` becomes `FORECAST_AZIMUTH=209`, etc. The
  per-roof slot scaffolding only appears for multi-roof setups (user8).
- **Privacy-redacted geocoords preserved verbatim.** Donor zeros the
  array's location with `FORECAST_LATITUDE=0.00000` /
  `FORECAST_LONGITUDE=0.00000` (with trailing whitespace on the latitude
  line) and comments out the real values. Round-trip keeps the zeros
  exactly; trailing whitespace is stripped by the env parser.
- **Watchtower `command: --scope solectrus --cleanup` transformed.** Same
  pattern as user7/user8: the `command:` override drops, flags become
  `WATCHTOWER_SCOPE=solectrus` and `WATCHTOWER_CLEANUP=true`. Donor uses
  the `nickfedor/watchtower` fork (untagged); export pins it to
  `nickfedor/watchtower:latest`.
- **`POWER_SPLITTER_INTERVAL=300`.** Donor sets the documented minimum
  (300s); HELIOS pins this var to a fixed `300` (5-minute cadence) for
  every stack regardless, so it round-trips unchanged here. Same fixed
  value as user8, where the donor left it undefined.
- **Forecast measurement spelled lowercase.** `INFLUX_MEASUREMENT_FORECAST=forecast`
  (lowercase) preserved as-is; differs from user8's `Forecast` (capital F)
  to confirm both casings round-trip without normalization.
- **Dozzle log viewer preserved unmanaged.** Same shape other fixtures
  exercise — Dozzle survives under `_unmanaged.services.dozzle` with its
  port `8080:8080` and read-only docker-socket mount.

## Lost or degraded on re-export (data loss)

- **Collector images forced to `:latest`.** Donor pinned
  `senec-collector`, `shelly-collector`, and `forecast-collector` to
  `:develop`; export rewrites them to `:latest`. HELIOS's collector
  service classes hardcode the tag, so the donor's choice of update
  channel (unstable develop vs. stable latest) is lost. `power-splitter`
  keeps its `:develop` tag because HELIOS records it in `config.yaml`.
- **Ingest service dropped — no balcony sensor.** Donor runs ingest with
  three SENEC MPPTs but no balcony power plant (all three slots share the
  `SENEC` measurement, so they're MPPTs of one inverter). HELIOS now
  derives ingest activation strictly from `is_balcony: true` sensors —
  without one, the service has nothing to recalculate. `ingest:` section
  absent from `config.yaml`, `ingest` service and the donor's `:develop`
  tag dropped on re-export. The donor's `forecast-collector` routing
  through `${INGEST_HOST}` already canonicalizes to direct InfluxDB
  writes (see "Equivalent on re-export"), so no consumer is left dangling.

## Equivalent on re-export (no operational impact)

These look like changes in the diff but don't alter what the stack
actually does — HELIOS's defaults match the donor's explicit values,
or the value is simply re-spelled.

- **`INFLUX_HOST=influxdb` / `INFLUX_PORT=8086` / `INFLUX_SCHEMA=http`**
  dropped — HELIOS bakes these into compose service-network addressing for
  every managed service.
- **`INFLUX_USERNAME=admin`** dropped from `.env`; HELIOS hardcodes
  `DOCKER_INFLUXDB_INIT_USERNAME=admin` in the InfluxDB service. Donor
  used the same value, so re-init against an empty volume would produce
  identical credentials.
- **InfluxDB `command:` override dropped.** Donor spelled out
  `influxd run --bolt-path /var/lib/influxdb2/influxd.bolt
  --engine-path /var/lib/influxdb2/engine --store disk` — these are the
  InfluxDB 2.x defaults under the image. Same as user7/user8.
- **Forecast routed through Ingest in donor compose, canonicalized direct.**
  Donor wires `forecast-collector` to write via `INFLUX_HOST=${INGEST_HOST}`
  / `INFLUX_PORT=${INGEST_PORT}`. Ingest's job is recalculating
  `house_power` for balcony plants, which forecast data doesn't need —
  export rewrites `forecast-collector` to talk directly to InfluxDB.
  Ingest passes forecast writes through unchanged today, so behavior is
  identical, but the canonical wiring is more honest.
- **Inline literal `INFLUX_TOKEN=${INFLUX_ADMIN_TOKEN}`** on
  `power-splitter` rewritten to `INFLUX_TOKEN=${INFLUX_TOKEN_READWRITE}`,
  which HELIOS aliases to the admin token by default. Same value resolved
  on both sides; the new variable name signals "this token needs both read
  and write access" so users can rotate it to a non-admin token later
  without touching compose.
- **`INGEST_HOST=ingest` / `INGEST_PORT=4567`** dropped — HELIOS bakes
  these into compose service-network addressing for collectors that
  write through Ingest.
- **`SENEC_HOST` / `SENEC_SCHEMA` / `SENEC_LANGUAGE` relocated.** Donor
  defines them at the top of `.env` (consumed by `senec-collector` in a
  hypothetical local-adapter setup). Donor actually runs the cloud
  adapter, so HELIOS's canonical SENEC section drops them — but
  `senec-charger` lists them as bare environment references and would
  crash on startup without them, so they reappear under the
  `senec-charger` section. Same value reaches every consumer either way.
- **`APP_HOST` filled in.** Donor commented `# APP_HOST=...` out, so the
  dashboard ran without an explicit host (relying on Rails default
  behavior). Export adds `APP_HOST=localhost`, the documented HELIOS
  default for non-Traefik deployments.
- **`WEB_CONCURRENCY` filled in at 0.** Donor commented out
  `WEB_CONCURRENCY=1` and `RAILS_MAX_THREADS=1`. Export emits
  `WEB_CONCURRENCY=0` (single-process Puma), which is what the dashboard
  effectively ran with.
- **`RETENTION_HOURS=12` added** for `ingest`. Donor didn't define it,
  meaning Ingest fell back to its image default. HELIOS now exports
  `RETENTION_HOURS=12` (the documented default) explicitly.
- **`WATCHTOWER_POLL_INTERVAL=86400` added.** Donor's command line had
  no poll-interval flag, so Watchtower used its image default. HELIOS
  exports `86400` (1 day) explicitly — same cadence the donor had been
  running implicitly.
- **Healthcheck timings normalized.** Donor's `interval: 30s` /
  `timeout: 10s` / `start_period: 10s|30s|60s` replaced with HELIOS's
  shorter standard intervals (`interval: 10s` / `timeout: 5s` plus a
  `start_interval: 2s`). Same probes, faster startup feedback.
- **`links: - influxdb` (legacy) dropped** from collectors and
  power-splitter. Compose v2 ignores `links` for service-network
  resolution; HELIOS doesn't re-emit it on managed services. The
  unmanaged `senec-charger` and `tibber-collector` keep their `links:`
  blocks because HELIOS preserves unmanaged services verbatim.
- **`env_file: .env` dropped from managed services.** Donor used
  `env_file: .env` for every collector and the dashboard; export emits an
  explicit `environment:` list with only the vars each service actually
  needs. Same vars resolved, smaller process env.
- **`nickfedor/watchtower` (untagged) → `nickfedor/watchtower:latest`.**
  Compose pulls the `latest` tag when none is specified; the explicit pin
  is what was already happening implicitly.
- **Sensor reordering on export.** Donor groups MQTT mappings in
  feature order (SENEC → custom-power → forecast → external); export
  sorts sensors alphabetically inside `config.yaml` and renders `.env`
  in HELIOS's canonical order.
