# user15

Real-world `compose.yaml` + `.env` from a SOLECTRUS user running a
**local-adapter SENEC V3** (three MPPTs) on a **Synology DSM** host,
with **five per-appliance Shelly collectors** (Fahrrad, plus four
kitchen items: Waschmaschine, Backofen, Spuelmaschine, Kuehlschrank),
an **openWB-fed wallbox + car** wired through the mqtt-collector, a
**two-roof pvnode (paid) forecast**, plus `power-splitter` and
`watchtower`. The fixture exercises two combinations that no prior
fixture covers: **openWB MQTT topics** (`openWB/chargepoint/4/get/*`,
`openWB/vehicle/0/get/soc`) routed into wallbox/car sensors, and the
canonical **`containrrr/watchtower`** image with a `--scope/--cleanup`
command line that has to split into env vars. Anonymized but otherwise
untouched.

## Imported correctly (round-trip preserves the value)

- **Five per-appliance shelly-collector services merged into one.**
  Donor declares `shelly-collector-Fahrrad`, `-Waschmaschine`,
  `-Backofen`, `-Kuehlschrank`, `-Spuelmaschine`, each parameterized by
  `SHELLY_HOST_<Name>` / `INFLUX_MEASUREMENT_SHELLY_<Name>`
  (capitalized German appliance names — `Fahrrad` is the bike-charging
  outlet). Importer matches by image and collapses to a single managed
  `shelly-collector` with comma-joined `SHELLY_HOST` and
  `INFLUX_MEASUREMENT` lists. Same merge pattern as user3 (German
  location names), user4 (numeric `-001..-005` suffixes), and user12
  (English appliance names); user15 keeps the **German appliance-named**
  variant honest.
- **openWB MQTT topics drive wallbox and car sensors.** Donor's three
  MAPPING slots wire
  `openWB/chargepoint/4/get/power` → `wallbox_power` (integer),
  `openWB/chargepoint/4/get/plug_state` → `wallbox_car_connected`
  (string), and `openWB/vehicle/0/get/soc` → `car_battery_soc` (float).
  All three round-trip as `source: mqtt` with the topic, measurement
  (`pv` / `pv` / `car`), field, and payload type preserved. First
  fixture exercising openWB topic naming (user10 covered evcc;
  user11 was pure-MQTT without a SENEC stack underneath) — confirms
  the MqttExtractor is broker-agnostic and topic-string-shape doesn't
  affect mapping resolution.
- **`INFLUX_EXCLUDE_FROM_HOUSE_POWER=WALLBOX_POWER` with MQTT-sourced
  wallbox.** Donor reads wallbox power off openWB via MQTT (not SENEC
  internals), and explicitly excludes it from the SENEC-side house-
  power total so the dashboard doesn't double-count. Re-export keeps
  `exclude_from_house_power: true` on `wallbox_power` and emits the
  same `WALLBOX_POWER` value in `.env`.
- **Three-MPPT SENEC V3 with no balcony heuristic trip.** Donor maps
  `INFLUX_SENSOR_INVERTER_POWER_1/_2/_3=SENEC:mpp1/mpp2/mpp3_power` —
  all three slots share the `SENEC:` measurement. Same shape as
  user5/user7/user13; measurement-divergence heuristic correctly keeps
  `is_balcony: false`. Empty `_4=` / `_5=` template slots drop via
  `well_formed_mapping?` (same path as user13).
- **pvnode (paid plan) two-roof forecast.** Donor sets
  `FORECAST_PROVIDER=pvnode`, `PVNODE_APIKEY=my-pvnode-apikey`,
  `PVNODE_PAID=true` (lowercase boolean — different from user3's
  uppercase `PVNODE_PAID=TRUE`), with two roofs at 23°/2.7 kWp (azimuth
  180° south) and 23°/3.0 kWp (azimuth 270° west). All twelve plane
  fields round-trip as strings; `config.yaml.forecast.forecast_pvnode_paid: 'true'`
  preserves the lowercase casing verbatim (forecast-collector accepts
  either form). First pvnode-paid fixture in the real_world set.
- **`SENEC_IGNORE=wallbox_charge_power` active.** Donor reads the
  wallbox via openWB MQTT, so SENEC's own `wallbox_charge_power` field
  would be a redundant (and lossier) source. Donor's `.env` sets the
  ignore list to suppress it; re-export keeps the value. Differs from
  user14's `SENEC_IGNORE=case_temp` and from user13's commented-out
  block — confirms the ignore-list survives with a non-default field
  name.
- **`INFLUX_SENSOR_INVERTER_POWER_FORECAST=forecast:watt` lowercase
  measurement.** Donor uses lowercase `forecast` for the measurement
  name (matches `INFLUX_MEASUREMENT_FORECAST=forecast`). Round-trip
  preserves the lowercase casing in both `config.yaml.forecast.measurement`
  and the sensor mapping. Same casing as user9 (vs user8/11/12/14's
  capitalized `Forecast`).
- **Remapped dashboard host port `3001:3000` preserved.** Donor binds
  the dashboard container's port `3000` to host port `3001` (probably
  because `3000` is taken on the host — Synology's own services often
  occupy low-3000 ports). Captured into `dashboard.host_port: '3001'`
  and re-emitted verbatim in the compose `ports:` block. Same shape as
  user13 (`3010:3000`); different port confirms the field carries the
  donor's choice rather than HELIOS guessing a value.
- **`FRAME_ANCESTORS=http://192.168.11.35:8123` (Home Assistant)
  preserved.** Donor embeds the dashboard inside HA's iframe card; the
  port `8123` and the host `192.168.11.35` (a Synology host, by
  convention `.10` = NAS, `.35` = HA VM) survive into
  `dashboard.frame_ancestors` and re-emit unchanged. Same shape as
  user8 but with a different HA host.
- **Single-token simplification: `INFLUX_TOKEN_WRITE` /
  `INFLUX_TOKEN_READ` / `INFLUX_ADMIN_TOKEN` all
  `my-super-secret-admin-token`.** Donor follows the documented
  "local/internal use" simplification (the comment in `.env.bak` lines
  286-287 explicitly endorses it). Round-trip keeps all three byte-
  identical and adds `INFLUX_TOKEN_READWRITE` set to the same value.
  Same shape as user13 (also single-token).
- **Power-splitter wired via `INFLUX_TOKEN=${INFLUX_ADMIN_TOKEN}`.**
  Same admin-token shortcut as user13/user14. HELIOS normalizes to
  `INFLUX_TOKEN=${INFLUX_TOKEN_READWRITE}` and synthesizes the
  matching `.env` entry (admin-token value carried through, but the
  canonical per-permission-role variable name now used on the
  power-splitter compose entry).
- **Synology DSM volume layout `/volume1/docker/solectrus/<service>`
  preserved.** Donor mounts `${INFLUX_VOLUME_PATH}` /
  `${DB_VOLUME_PATH}` / `${REDIS_VOLUME_PATH}` to absolute paths under
  `/volume1/docker/solectrus/...` rather than the canonical ADR-0003
  relative `./influxdb` layout. Same shape as user12; round-trip
  passes the absolute paths through verbatim (HELIOS doesn't rewrite
  to relative).
- **`INFLUX_MEASUREMENT_SHELLY_<Name>=...` indirection collapsed.**
  Donor's compose uses
  `INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_SHELLY_Fahrrad}` etc. per
  service; HELIOS rewrites the merged shelly-collector to a single
  `INFLUX_MEASUREMENT` env line that resolves through the comma-joined
  list. Measurement strings (`Fahrrad`, `Waschmaschine`, …) survive
  unchanged.
- **`INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_SENEC}` indirection
  collapsed.** Same canonicalization as user12/13/14. Measurement
  string `SENEC` survives unchanged.
- **`INFLUX_SENSOR_HEATPUMP_POWER=` template slot dropped.** Donor's
  `.env` declares the empty slot; compose dashboard env block omits
  it from the passthrough list. Drops via `well_formed_mapping?`,
  same path as user13's full template-empty block.
- **`INSTALLATION_DATE=2020-01-01` preserved as `'2020-01-01'`.**
  Six-year-old install, same quoted-ISO-string shape as user13.
- **`APP_HOST=192.168.11.10` (raw IPv4) preserved.** Donor reaches the
  dashboard by IP (the `.10` slot in the Synology subnet); same shape
  as user13/14's IPv4 hosts.
- **Older pinned image versions preserved.** `postgres:17-alpine`,
  `redis:7-alpine`, `influxdb:2.7-alpine` — donor pins minor versions
  one major behind HELIOS's emit defaults (user13 ships `postgres:18`
  / `redis:8` / `influxdb:2-alpine`). Round-trip keeps the donor's
  pinned tags byte-identical (HELIOS doesn't upgrade-nudge).
- **Watchtower `containrrr/watchtower` (no tag) → `:latest`, command
  → env vars.** Donor runs the canonical (not `nickfedor/` fork)
  watchtower image without an explicit tag; HELIOS imports as
  `containrrr/watchtower:latest`. Donor's bare
  `command: --scope solectrus --cleanup` splits to
  `WATCHTOWER_SCOPE=solectrus` / `WATCHTOWER_CLEANUP=true`, plus
  default `WATCHTOWER_POLL_INTERVAL=86400`. Same canonicalization as
  user6/12/13/14, here on the original `containrrr` image (user8 was
  also containrrr but didn't exercise the command-split path).

## Equivalent on re-export (no operational impact)

These look like changes in the diff but don't alter what the stack
actually does — HELIOS's defaults match the donor's explicit values,
the value is simply re-spelled, or the var was already dead at runtime.

- **Duplicate `TZ=Europe/Berlin` collapsed.** Donor declares
  `TZ=Europe/Berlin` twice in `.env.bak` — once in the general block
  (line 5) and once in the forecast block (line 183). dotenv applies
  last-write-wins (same value either way); HELIOS emits a single
  canonical `TZ=Europe/Berlin` in the general block. Same shape as
  user7.
- **InfluxDB `command: influxd run --bolt-path ... --engine-path ...
  --store disk` dropped.** Donor's explicit-defaults override removed
  (same as user7-14).
- **InfluxDB `ports: 8086:8086` added.** Donor doesn't expose the
  port; HELIOS publishes it unconditionally for InfluxDB UI access.
  Same as user11/12/13.
- **`INFLUX_HOST=influxdb` / `INFLUX_PORT=8086` / `INFLUX_SCHEMA=http`
  / `INFLUX_USERNAME=my-influx-username` dropped from `.env`.** HELIOS
  bakes the connection into compose service-network addressing and
  hardcodes the admin username on export. Donor's
  `INFLUX_USERNAME=my-influx-username` is overwritten to the standard
  `admin` (the InfluxDB volume on first init bakes whatever username
  was set; on a fresh volume HELIOS's `admin` takes effect, on an
  existing volume the donor's value remains in the init record but
  is unreachable through HELIOS).
- **`links: - influxdb` blocks dropped from every collector.** Legacy
  compose feature; modern bridge-network service discovery makes them
  no-ops. Same as user12/13/14.
- **`INFLUX_SCHEMA` / `INFLUX_PORT` dropped from collector env.**
  Donor passes them through (`- INFLUX_SCHEMA`, `- INFLUX_PORT`);
  HELIOS bakes the connection into the in-network default
  `http://influxdb:8086`. Same as user13/14.
- **Empty `UI_THEME` / `CO2_EMISSION_FACTOR` passthroughs dropped
  from dashboard env.** Donor lists them as bare references in
  compose but never sets values in `.env` (the template-comment
  forms remain `# `-prefixed). HELIOS drops the dead env lines (same
  as user13/14).
- **`REDIS_URL=redis://redis:6379/1` inlined.** Donor wires it
  through `.env` + `- REDIS_URL` passthrough; HELIOS inlines the
  literal in dashboard and power-splitter env blocks and drops the
  `.env` entry. Same as user12/13/14.
- **`POWER_SPLITTER_INTERVAL=3600` emitted (donor had it commented).**
  Donor's `.env.bak` leaves `# POWER_SPLITTER_INTERVAL=3600`
  commented; at runtime the collector falls back to its built-in
  default (also `3600`). HELIOS emits the documented default
  explicitly. Same as user13/14.
- **`POSTGRES_DB=solectrus` / `DB_DATABASE=solectrus` added.** Donor
  relied on the postgres image default (also `solectrus`); HELIOS
  sets the name explicitly. Same as user12/13/14.
- **`POSTGRES_PASSWORD` plain passthrough added to power-splitter
  env.** Donor only wires `DB_PASSWORD=${POSTGRES_PASSWORD}`; HELIOS
  adds the raw `POSTGRES_PASSWORD` passthrough too. Same as user13/14.
- **`WEB_CONCURRENCY=0` emitted explicitly.** Donor sets it to `0`
  already; HELIOS keeps the documented default (single-process Puma).
- **Empty `INFLUX_SENSOR_INVERTER_POWER_4..5` + `_CUSTOM_POWER_06..20`
  passthroughs dropped from dashboard compose env.** Donor lists all
  15 unused `CUSTOM_POWER_06..20` slots and 2 unused `INVERTER_POWER_4/5`
  slots in the dashboard `environment:` block (template residue), but
  `.env.bak` only sets `INVERTER_POWER_4=` / `_5=` (empty) and doesn't
  declare `CUSTOM_POWER_06..20` at all. All 17 dead references drop
  on re-export — same path as user13's bare-passthrough cleanup, just
  on a denser slate.
- **Upstream-template documentation comments stripped.** Donor's
  `.env.bak` lines 198-249 carry a long block of forecast.solar /
  solcast / FORECAST_DAMPING / FORECAST_2-3 / PVNODE_EXTRA_PARAMS
  comment-examples copied verbatim from the upstream template. None
  is active. HELIOS emits clean per-block headers without the
  donor's residual template comments. Same hygiene as user13/14.
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
