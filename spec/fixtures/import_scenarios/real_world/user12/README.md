# user12

Real-world `docker-compose.yml` + `.env` from a SOLECTRUS user running a
classic SENEC stack with **six per-appliance Shelly collectors** (heat
pump, dishwasher, beamer, washing machine, dryer, microwave) and a
two-plane forecast.solar setup with placeholder coordinates. The donor
exercises the importer's **orphan-mapping heal**: the dashboard's
`environment:` block lists only `INFLUX_SENSOR_CUSTOM_POWER_01..05`,
yet `.env` carries `INFLUX_SENSOR_CUSTOM_POWER_06=dishwasher:power`
and the corresponding `shelly-collector-dishwasher` service is
actively writing to InfluxDB measurement `dishwasher` — the donor
typo'd themselves into silent data loss (Shelly writes, dashboard
never reads). HELIOS reads `INFLUX_SENSOR_*` from `.env` directly,
not via the dashboard's interpolated env, so the orphan is preserved
as a managed sensor and the round-trip re-wires it through the
dashboard. The fixture also exercises the **literal-placeholder
filter**: `INFLUX_SENSOR_WALLBOX_CAR_CONNECTED=false` /
`INFLUX_SENSOR_CAR_BATTERY_SOC=0` aren't `measurement:field`
references and are correctly dropped. Anonymized but otherwise
untouched.

## Imported correctly (round-trip preserves the value)

- **Six per-appliance shelly-collector services merged into one.**
  Donor declares `shelly-collector-heatpump`, `-dishwasher`,
  `-beamer`, `-washingmashine` (typo preserved), `-dryer`,
  `-microwave`, each parameterized by
  `SHELLY_HOST_<APPLIANCE>` / `INFLUX_MEASUREMENT_SHELLY_<APPLIANCE>`.
  Importer matches by image and merges into a single managed
  `shelly-collector` with comma-joined `SHELLY_HOST` and
  `INFLUX_MEASUREMENT` lists — same merge pattern as user3 (German
  location-named suffixes) and user4 (numeric `-001..-005` suffixes);
  this fixture keeps the **English appliance-named** variant honest.
- **Orphaned `INFLUX_SENSOR_CUSTOM_POWER_06=dishwasher:power`
  rescued.** Donor's `.env` defines the mapping AND the
  `shelly-collector-dishwasher` service writes to InfluxDB measurement
  `dishwasher` AND `SHELLY_HOST_DISHWASHER=192.168.178.80` is set —
  but `dashboard.environment:` only lists
  `INFLUX_SENSOR_CUSTOM_POWER_01..05`, so the dashboard never reads
  slot 06. The Shelly was writing data that no one consumed. HELIOS
  reads `INFLUX_SENSOR_*` from `.env` directly (not just from the
  dashboard's interpolated env), so `custom_power_06` imports as a
  managed Shelly sensor with `measurement: dishwasher`,
  `shelly_host: 192.168.178.80`, `name: dishwasher`. On re-export
  the dishwasher reappears in every CSV list (`SHELLY_HOST` has 6
  entries, `INFLUX_MEASUREMENT` has 6) AND the dashboard now
  receives `INFLUX_SENSOR_CUSTOM_POWER_06` through its env block.
  Donor's silent data loss becomes a working sensor — same heal-on-
  rename pattern as user4 (`db:` → `postgresql:` repaired a typo'd
  `DB_HOST=postgresql`), but on the sensor side.
- **Literal-value sensor placeholders dropped.**
  `INFLUX_SENSOR_WALLBOX_CAR_CONNECTED=false` and
  `INFLUX_SENSOR_CAR_BATTERY_SOC=0` are scalar literals, not
  `measurement:field` references — the donor used them to hardcode
  dashboard values (no car connected, no SoC) rather than wiring a
  real sensor. The same `.env`-first reader that rescues the
  dishwasher would also pick these up, but `SensorsExtractor#well_formed_mapping?`
  rejects values whose `split(':', 2)` halves aren't both present.
  Neither appears as a sensor in `config.yaml` and neither is re-emitted
  on export. The dashboard falls back to whatever its built-in default
  is for an absent mapping (same outcome as the donor's intent).
- **SENEC sensors synthesized from `INFLUX_MEASUREMENT_PV=SENEC`.**
  Donor's `.env` defines no `INFLUX_SENSOR_INVERTER_POWER`,
  `_GRID_IMPORT_POWER`, `_HOUSE_POWER`, `_BATTERY_*`, `_WALLBOX_POWER`,
  `_CASE_TEMP`, `_SYSTEM_STATUS*`, `_GRID_EXPORT_LIMIT` — only the 6
  CUSTOM_POWER slots. With `INFLUX_MEASUREMENT_PV=SENEC` set,
  `LegacySensorAdapter` flips into legacy mode and the fallback table
  resurrects all 11 SENEC sensors with the canonical
  `SENEC:<field>` mappings (same mechanism as user4). Re-export
  materializes the full SENEC sensor block in `.env`; the dashboard
  reads the exact values it would have served from defaults anyway.
- **`inverter_power_forecast` auto-added from forecast-collector
  presence.** Donor never sets `INFLUX_SENSOR_INVERTER_POWER_FORECAST`
  in `.env`, but the forecast-collector service writes to
  `INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_FORECAST}` (=`Forecast`).
  Legacy fallback synthesizes the sensor as
  `forecast` source with `measurement: Forecast`, `field: watt`;
  export emits `INFLUX_SENSOR_INVERTER_POWER_FORECAST=Forecast:watt`.
- **`INFLUX_MEASUREMENT_PV=SENEC` / `INFLUX_MEASUREMENT_FORECAST=Forecast`
  (capitalized) preserved.** Same as user11 — round-trip keeps the
  uppercase casing. Variable name changes (`INFLUX_MEASUREMENT_PV` →
  `INFLUX_MEASUREMENT_SENEC` on export, matching HELIOS's canonical
  per-collector naming) but the measurement string itself is
  byte-identical.
- **forecast.solar two-roof setup with placeholder coordinates.**
  Donor sets `FORECAST_LATITUDE=0.00000` /
  `FORECAST_LONGITUDE=0.00000` (Null Island — a deliberate stub the
  donor never filled in) and `FORECAST_CONFIGURATIONS=2` with
  `FORECAST_0_DECLINATION=40` / `_AZIMUTH=-53.6` / `_KWP=6.750` and
  `FORECAST_1_DECLINATION=40` / `_AZIMUTH=126.4` / `_KWP=5.250`.
  Importer preserves the placeholders verbatim — no auto-fix, no
  warning — and exports `forecast_latitude: '0.00000'`,
  `forecast_longitude: '0.00000'` so the donor can correct them
  through the HELIOS UI without HELIOS guessing.
- **Default forecast provider (forecast.solar) inferred from absent
  `FORECAST_PROVIDER`.** Donor never sets `FORECAST_PROVIDER`, the
  forecast-collector's documented default is `forecast.solar`, and
  donor populates only the geometry vars (lat/lon/declination/azimuth/kwp)
  — never `SOLCAST_*` or `PVNODE_*`. Importer takes forecast.solar
  as the provider; `SOLCAST_*` / `PVNODE_*` references in the
  forecast-collector's compose `environment:` block stay empty and
  are dropped, only the active forecast.solar slots survive.
- **`FORECAST_DAMPING_MORNING=0.5` / `_EVENING=0.2` preserved.**
  Donor's non-default damping coefficients survive round-trip; export
  emits the same `0.5` / `0.2` values.
- **`FORECAST_0_AZIMUTH=-53.6` quoted as `'-53.6'` in YAML.** Leading
  `-` triggers the quote, same as user4's `'-115'`.
- **Watchtower with `nickfedor/watchtower` canonicalized.** Donor
  runs the fork without an explicit tag; HELIOS imports as
  `nickfedor/watchtower:latest` (same as user1/user3/user11). Donor's
  bare `command: --scope solectrus --cleanup` collapses into
  `WATCHTOWER_SCOPE=solectrus` / `WATCHTOWER_CLEANUP=true` env-var
  form with the default `WATCHTOWER_POLL_INTERVAL=86400`.
- **`INSTALLATION_DATE=2023-01-01` preserved.** Round-trips as a
  quoted ISO string in `config.yaml` and re-emits unchanged in `.env`.
- **Postgres password indirection `DB_PASSWORD=${POSTGRES_PASSWORD}`
  preserved.** Same pattern as user11 — donor wires it through
  explicitly, HELIOS keeps the same indirection on export.

## Equivalent on re-export (no operational impact)

These look like changes in the diff but don't alter what the stack
actually does — HELIOS's defaults match the donor's explicit values,
the value is simply re-spelled, or the var was already dead at runtime.

- **`version: '3.7'` top-level attribute dropped.** Obsolete since
  Compose Spec 1.27 (current Compose ignores it and emits a warning).
  HELIOS doesn't carry it forward.
- **`links:` blocks dropped from every service.** Donor uses the
  legacy `links: - influxdb` / `- db` / `- redis` pattern across
  dashboard and all collectors. Modern Compose service discovery on
  the default bridge network makes `links:` unnecessary; HELIOS
  drops them all.
- **`db:` service renamed to `postgresql:`; `/data` subpath stripped
  from the bind mount.** Donor mounts
  `${DB_VOLUME_PATH}:/var/lib/postgresql/data`; HELIOS rewrites to
  `${DB_VOLUME_PATH}:/var/lib/postgresql` (ADR-0003 bind-mount
  layout). Same regression-guard as user10.
- **`INFLUX_HOST=influxdb` / `INFLUX_PORT=8086` / `INFLUX_SCHEMA=http`
  / `INFLUX_USERNAME=admin` dropped from `.env`.** HELIOS bakes
  these into compose service-network addressing and hardcodes the
  admin username. Donor used the documented defaults, so re-init
  against an empty volume produces identical credentials. Same as
  user10/user11.
- **InfluxDB `command: influxd run --bolt-path ... --engine-path ...
  --store disk` dropped.** These are the InfluxDB 2.x image defaults
  (same as user7/user8/user9/user10/user11).
- **InfluxDB UI port stays unpublished.** Donor has the block
  commented out (`# Optional: Allow InfluxDB to be accessed from the
  outside.`); import captures no `influxdb.publish_port` flag, and
  the re-exported `influxdb` service has no `ports:` block. Same as
  user11.
- **InfluxDB write/read token aliases collapsed.** Donor defines
  `INFLUX_TOKEN_WRITE=my-influx-write-token` /
  `INFLUX_TOKEN_READ=my-influx-read-token` separately from
  `INFLUX_ADMIN_TOKEN`. HELIOS additionally introduces
  `INFLUX_TOKEN_READWRITE=my-influx-admin-token` for the new
  power-splitter; aliases resolve consistently across services.
- **Power-splitter service added.** Donor compose has no
  `power-splitter`; HELIOS adds it as a managed service with
  `POWER_SPLITTER_INTERVAL=3600` (default). Same as user10.
- **`POSTGRES_DB=solectrus` / `DB_DATABASE=solectrus` added.** Donor
  relied on the postgres image default (also `solectrus`); HELIOS
  sets the name explicitly.
- **`REDIS_URL=redis://redis:6379/1` inline in compose.** Donor
  already inlines the literal in dashboard env (no `.env`
  indirection); HELIOS keeps the same shape.
- **HELIOS service added.** Self-export.
- **`name: solectrus` and `networks.default.name: solectrus_default`
  added.** Donor compose has neither (relies on the implicit project
  name from the directory).
- **`WEB_CONCURRENCY=0` added.** Donor never set it; HELIOS emits
  the documented default (single-process Puma).
- **`INFLUX_POLL_INTERVAL` listed in `dashboard.environment:` but
  not defined in `.env`.** Was empty at runtime; HELIOS emits the
  documented default (`INFLUX_POLL_INTERVAL=5`).
- **`SHELLY_PASSWORD` referenced in shelly-collector env but never
  set in `.env`.** All six donor Shelly services list
  `- SHELLY_PASSWORD`, but `.env` defines no value — Shelly auth was
  effectively off. HELIOS doesn't carry the dead reference forward.
- **`SHELLY_INTERVAL=10` repeated six times in `.env` collapsed to
  one.** Donor redefines the same value at the end of every Shelly
  appliance block. Last-write-wins, so all six entries already
  resolve to `10`; HELIOS exports a single `SHELLY_INTERVAL=10`.
- **`ELECTRICITY_PRICE=0.2526` / `FEED_IN_TARIFF=0.082` dropped.**
  Legacy dashboard-only env vars, today managed via the UI as
  historical prices. Listed in `LEGACY_CONSUMED_ENV_KEYS` so they're
  silently dropped on import (same as user4).
- **Trailing whitespace on `dashboard.image:` value trimmed.** Donor
  has `ghcr.io/solectrus/solectrus:develop ` (trailing space at line
  5); importer normalizes, export emits the trimmed form.
- **Healthcheck timings normalized.** Donor's `interval: 30s|10s` /
  `timeout: 10s|20s` / `start_period: 10s|30s|60s` replaced with
  HELIOS's shorter standard intervals (`interval: 10s` / `timeout: 5s`
  plus a `start_interval: 2s`). Same probes, faster startup feedback.
- **Empty forecast geometry vars not emitted twice.** Donor's compose
  lists every slot
  (`FORECAST_DECLINATION`, `FORECAST_AZIMUTH`, `FORECAST_KWP`,
  `FORECAST_INVERTER`, `FORECAST_0/1/2/3_*`, `FORECAST_SOLAR_APIKEY`,
  `SOLCAST_*`, `PVNODE_*`); only the two active roofs survive. Same
  shape as user4.
- **Commented-out alternatives dropped.** `# FORECAST_2_DECLINATION`
  through `# FORECAST_3_KWP`, the `# FORECAST_DECLINATION/AZIMUTH/KWP`
  single-roof examples, and the inline single-roof example block —
  all removed on re-export (HELIOS only emits active values).
- **Sensor reordering on export.** Donor groups sensors loosely;
  export sorts sensors alphabetically inside `config.yaml` and
  renders `.env` in HELIOS's canonical block order.
