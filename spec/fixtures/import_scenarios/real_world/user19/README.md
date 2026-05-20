# user19

Real-world `docker-compose.yml.bak` + `.env.bak` from a SOLECTRUS user
running a **local-adapter SENEC V3** (`SENEC_SCHEMA=https`,
`SENEC_HOST=192.168.178.128`) with a single-roof **forecast.solar**
forecast and `watchtower`. No power-splitter in the donor stack, no
Shelly, no MQTT, no heat pump — a stripped-down SENEC-only setup that
predates several HELIOS-era conventions.

The fixture's headline quirk is a **forecast-collector with no
`FORECAST_PROVIDER` anywhere** — neither in `.env` nor in the
`forecast-collector` compose `environment:` block. The collector's
documented default is `forecast.solar`
(`ENV.fetch('FORECAST_PROVIDER', 'forecast.solar')` in the
forecast-collector source). Before this fixture, the importer stored a
`nil` provider, `compact` dropped the `forecast` key, and the exporter's
`ForecastCollector.enabled?` (which requires `forecast.forecast.present?`)
silently dropped the **entire forecast-collector service** — total data
loss for every old-style forecast.solar stack. The importer now mirrors
the collector's default, so a provider-less collector round-trips
intact. See `ForecastExtractor#provider`.

Two more donor traits exercise the importer: the **legacy `app` / `db`
service names** (renamed to `dashboard` / `postgresql`), and a single
**empty `INFLUX_SENSOR_WALLBOX_POWER=`** that the importer respects as
an explicit user opt-out (no wallbox). Anonymized but otherwise untouched.

## Imported correctly (round-trip preserves the value)

- **`FORECAST_PROVIDER` absent → `forecast.solar` default.** Donor's
  `.env` and `forecast-collector` compose env never mention
  `FORECAST_PROVIDER`; the donor only sets the geometry vars
  (`FORECAST_LATITUDE` / `_LONGITUDE` / `_DECLINATION` / `_AZIMUTH` /
  `_KWP`) and `FORECAST_INTERVAL`. The importer takes `forecast.solar`
  as the provider (the collector's documented fallback), exports
  `FORECAST_PROVIDER=forecast.solar` explicitly, and keeps the
  forecast-collector service alive. Same default as user12, but user19
  is the **clean minimal reproduction**: no multi-roof config, no API
  key, nothing but the bare geometry — the exact shape that previously
  vanished on export.
- **`docker-compose.yml.bak` filename variant.** Same slot in
  `Compose::FILENAMES` as user3/4/12/16/18.
- **Single-roof forecast.solar geometry preserved.** `.env` sets the
  unprefixed `FORECAST_DECLINATION=30`, `FORECAST_AZIMUTH=10`,
  `FORECAST_KWP=9.9`. With no `FORECAST_CONFIGURATIONS`, the importer
  treats the stack as single-roof (`forecast_roofs: '1'`) and maps the
  unprefixed values into the `forecast_declination1` /
  `forecast_azimuth1` / `forecast_kwp1` slots. `FORECAST_INTERVAL=900`
  preserved at the 15-minute floor for the free forecast.solar tier.
- **`FORECAST_LATITUDE=0.00000` / `FORECAST_LONGITUDE=0.00000`
  placeholder geo preserved.** Donor anonymized the coordinates to the
  null island; HELIOS treats them as opaque strings and re-emits
  `'0.00000'` byte-identical. Same null-island placeholder as
  user12/16/18.
- **Empty `INFLUX_SENSOR_WALLBOX_POWER=` respected as user opt-out.**
  Donor's `.env` sets 12 sensors explicitly as `SENEC:*` /
  `Forecast:watt` mappings and leaves `INFLUX_SENSOR_WALLBOX_POWER=`
  blank — the user has no wallbox. Even with the dashboard env carrying
  `INFLUX_MEASUREMENT_PV` / `INFLUX_MEASUREMENT_FORECAST` (which flips
  `LegacySensorAdapter.legacy_mode?` to active), the adapter skips any
  sensor whose `INFLUX_SENSOR_*` key is present in the env regardless of
  value, so the blank slot drops on re-export instead of being healed
  into `SENEC:wallbox_charge_power`. The 12 explicit mappings round-trip
  byte-identical.
- **`/home/user19/solectrus/<service>` volume layout preserved.**
  Donor mounts the three `${X_VOLUME_PATH}` envs to absolute home
  paths; round-trip passes them through verbatim (HELIOS doesn't
  rewrite to the ADR-0003 relative layout).
- **`influxdb:2.7-alpine`, `postgres:16-alpine`, `redis:7-alpine`
  pinned older tags preserved.** Donor pins each to a tag behind
  HELIOS's emit defaults; round-trip keeps them byte-identical (no
  upgrade-nudge). Same as user16.
- **Single-token simplification.** Donor sets `INFLUX_TOKEN_WRITE` and
  `INFLUX_TOKEN_READ` to the same `my-influx-admin-token` as
  `INFLUX_ADMIN_TOKEN` — the "local/internal use" shortcut from the
  upstream `.env` template. Round-trip keeps all three byte-identical
  and adds `INFLUX_TOKEN_READWRITE` (synthesized for the auto-added
  power-splitter — see _Equivalent on re-export_).

## Equivalent on re-export (no operational impact)

- **29 dead multi-plane `FORECAST_*` passthroughs dropped.** Donor's
  `forecast-collector` compose `environment:` block lists
  `FORECAST_CONFIGURATIONS` plus the full `FORECAST_0_*`…`FORECAST_3_*`
  matrix (4 planes × 7 vars). None is defined in `.env` — they are the
  upstream template's commented-out multi-plane examples, copied bare
  into the compose env list. The importer reads only the unprefixed
  single-roof geometry; all 29 prefixed passthroughs are dead
  references and drop on re-export.
- **Legacy `app` / `db` service names renamed.** Donor names the main
  service `app` and the database `db` (the historic SOLECTRUS naming).
  HELIOS canonicalizes to `dashboard` / `postgresql` and rewrites
  `DB_HOST=db` → `DB_HOST=postgresql`.
- **Power-splitter service added.** Donor compose has no
  `power-splitter`; HELIOS adds it as a managed service with
  `POWER_SPLITTER_INTERVAL=3600` (default) and synthesizes
  `INFLUX_TOKEN_READWRITE` from the donor's admin token. Same auto-add
  as user10/12/16.
- **`INFLUX_USERNAME=my-influx-username` replaced with `admin`.** Donor
  set a custom InfluxDB init username; HELIOS hardcodes the canonical
  `admin` on export (`DOCKER_INFLUXDB_INIT_USERNAME=admin`). Init-only
  value — no operational impact after first start.
- **`INFLUX_HOST=influxdb` / `INFLUX_SCHEMA=http` / `INFLUX_PORT=8086`
  dropped from `.env`.** HELIOS bakes the connection into compose
  service-network addressing. `INFLUX_SCHEMA` / `INFLUX_PORT` likewise
  dropped from the senec-collector env passthrough.
- **`INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_PV}` canonicalized to
  `INFLUX_MEASUREMENT_SENEC`.** Donor's senec-collector uses the
  PV-named indirection; HELIOS rewrites it to a bare
  `INFLUX_MEASUREMENT_SENEC` passthrough and writes
  `INFLUX_MEASUREMENT_SENEC=SENEC` in `.env`. The
  `INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_FORECAST}` indirection on
  the forecast-collector is preserved unchanged.
- **Watchtower `command` split to env vars.** Donor runs
  `containrrr/watchtower` (untagged) with `command: --scope solectrus
--cleanup`. HELIOS pins `containrrr/watchtower:latest` and splits
  the flags to `WATCHTOWER_SCOPE=solectrus` /
  `WATCHTOWER_CLEANUP=true`, plus the default
  `WATCHTOWER_POLL_INTERVAL=86400`.
- **InfluxDB `command: influxd run --bolt-path … --engine-path … --store
disk` dropped.** Donor's explicit-defaults override removed.
- **`REDIS_URL=redis://redis:6379/1` kept inline.** Donor inlines it
  on the `app` env block; HELIOS preserves it inline on `dashboard`
  and propagates the same literal to the auto-added power-splitter.
- **`POSTGRES_DB=solectrus` / `DB_DATABASE=solectrus` added.** Donor
  relied on the postgres image default (also `solectrus`); HELIOS sets
  the name explicitly.
- **`WEB_CONCURRENCY=0` emitted explicitly.** Donor doesn't set it;
  HELIOS adds the documented default (single-process Puma).
- **`links:` blocks dropped from `app` and every collector.** Legacy
  compose feature; modern bridge-network service discovery makes them
  no-ops.
- **`restart: always` → `restart: unless-stopped` on every managed
  service.** Donor uses `always` throughout; HELIOS normalizes to
  `unless-stopped` (operator-initiated stops honored either way).
- **`logging.driver: json-file` added uniformly.** Donor sets no
  explicit logging; HELIOS normalizes every service to the docker
  default driver, made explicit.
- **Healthcheck timings normalized.** Donor's per-service intervals
  (`30s` / `10s`) and start-periods replaced with HELIOS's standard
  `interval: 10s` / `timeout: 5s` / `start_interval: 2s`.
- **Upstream-template documentation comments stripped.** Donor's
  `.env.bak` carries the upstream forecast.solar template block
  (multi-plane examples, damping factors, API-key hints) — all
  commented-out and inactive. HELIOS emits clean per-block headers
  without the residual template comments.
- **Legacy `# version: '3.7'` header comment dropped.** HELIOS emits
  its own canonical header block.
- **Trailing whitespace on `INFLUX_SENSOR_SYSTEM_STATUS_OK   ` in the
  `app` env list dropped.** Compose env entries are re-emitted clean.
- **`name: solectrus` and `networks.default.name: solectrus_default`
  added.** Donor has neither.
- **HELIOS service added.** Self-export.
- **Sensor reordering on export.** Export sorts sensors alphabetically
  in `config.yaml` and renders `.env` in HELIOS's canonical block
  order.
