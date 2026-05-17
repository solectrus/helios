# user18

Real-world `docker-compose.yml.bak` + `.env.bak` from a SOLECTRUS user
running a **local-adapter SENEC V3** (`SENEC_SCHEMA=https`,
`SENEC_HOST=192.168.3.100`) with **forecast.solar** forecasts, the
official **power-splitter** managed service, and two non-canonical
SOLECTRUS collectors that HELIOS does not manage: **`tibber-collector`**
(writes spot prices to `INFLUX_MEASUREMENT_PRICES=Tibber`) and
**`senec-charger`** (reads prices + forecast and conditionally pulses
the SENEC battery into grid-charge mode). The donor's dashboard image
is pinned to a **PR build (`ghcr.io/solectrus/solectrus:pr-3747`)**,
not `:latest` / `:develop`, and the donor uses **compose schema
`version: "3.7"`** as the top-level literal (legacy, ignored by modern
`docker compose`). Anonymized but otherwise untouched.

The fixture exercises one quirk no prior fixture covers: a fleet of
**nine per-device `shelly-collector-*` services** (`-tv`, `-gsa`,
`-oven`, `-oven2`, `-wa`, `-wa2`, `-dryer`, `-dryer2`, `-mw`) — one
container per Shelly plug. HELIOS's `ShellyExtractor` aggregates every
service into a single `shelly.devices` list (the multi-device source of
truth) and the export collapses the fleet into one canonical
`shelly-collector` container with CSV-valued `SHELLY_HOST` and
`INFLUX_MEASUREMENT`. The donor's per-device measurements are
case-mismatched against the dashboard's `INFLUX_SENSOR_CUSTOM_POWER_*`
mappings (collector writes `tv` lowercase, dashboard reads `TV`
uppercase), so the broken pipeline is faithfully reproduced — sensors
land as `source: external` because no managed measurement aligns, but
the collector containers themselves round-trip cleanly under the
HELIOS-canonical multi-device shape.

Three smaller first-of-its-kind quirks ride along: **`senec-charger`**
as the second unmanaged SOLECTRUS service (after user17's MQTT-only
shape, but this is the first one drawing from `INFLUX_TOKEN_READ`
rather than the write token), **`tibber-collector`** writing to a
non-canonical `INFLUX_MEASUREMENT_PRICES` slot, and a **legacy
mixed-case env var typo** in the donor's compose (`${SHELLY_HOST_dryer}`
/ `${SHELLY_GEN_dryer}` referencing lowercase, while `.env.bak`
declares `SHELLY_HOST_DRYER=...` / `SHELLY_GEN_DRYER=...` uppercase
— docker compose's case-sensitive interpolation silently fails, so the
dryer collector boots with empty `SHELLY_HOST` and `SHELLY_GEN`, and
HELIOS drops the entry from `shelly.devices` because there is no host
to attach it to).

## Imported correctly (round-trip preserves the value)

- **Multi-instance Shelly fleet canonicalized into one `shelly-collector`
  with CSV-valued `SHELLY_HOST` / `INFLUX_MEASUREMENT`.** Donor runs
  one container per plug (`shelly-collector-tv`, `-gsa`, `-oven`,
  `-oven2`, `-wa`, `-wa2`, `-dryer2`, `-mw`); HELIOS aggregates them
  into `shelly.devices` (eight entries — the dryer drops out, see
  below) and exports a single canonical container that reads the same
  data via CSV. `name:` per device is taken from the `${SHELLY_HOST_<NAME>}`
  reference in the raw compose (`tv`, `gsa`, …), with the offset-based
  `deviceN` fallback reserved for literal-CSV donors. First fixture
  exercising the per-device-services topology with measurement
  case-mismatches mixed in.
- **Eight `SHELLY_HOST_*` IPs absorbed into `shelly.devices` and
  re-emitted as a single CSV `SHELLY_HOST=192.168.3.95,192.168.3.90,
…`.** Donor's `SHELLY_HOST_TV=192.168.3.89` etc. are managed via
  `managed_shelly_env_key?` and round-trip through the canonical
  multi-device shape instead of `_unmanaged.env_vars`. The ninth host
  (`SHELLY_HOST_DRYER`) does not survive — the donor's compose
  references `${SHELLY_HOST_dryer}` (lowercase suffix, line 209) while
  `.env.bak` declares `SHELLY_HOST_DRYER=...` (uppercase, line 38),
  and docker compose's `${VAR}` interpolation is case-sensitive, so the
  importer never sees a host to attach to that device.
- **Dashboard pinned to a PR build (`ghcr.io/solectrus/solectrus:pr-3747`).**
  First fixture where the donor runs a pull-request preview build
  rather than `:latest` / `:develop` / a semver tag. The full tag
  survives byte-identical through `dashboard.image` in `config.yaml`
  and the `dashboard:` block in `compose.yaml`. HELIOS treats it as
  an opaque string — no validation, no nudge to switch back to a
  stable channel.
- **`SENEC_SCHEMA=https`** preserved alongside `SENEC_HOST=192.168.3.100`.
  Donor uses HTTPS for the local SENEC (most fixtures use the default
  `http`). The value rides through `senec.schema: https` in
  `config.yaml` and re-emits as the same line in `.env`. Same shape as
  user14 but the first fixture pairing `https` with a `192.168.x.x`
  RFC1918 host (i.e. self-signed cert on a local appliance —
  operationally valid because the senec-collector skips TLS
  verification).
- **Single-token simplification with split write/read declarations.**
  Donor sets `INFLUX_TOKEN_WRITE=my-super-secret-admin-token` and
  `INFLUX_TOKEN_READ=my-super-secret-admin-token` (both pointing at the
  same admin token literal, but split into two named slots — the
  pattern the upstream `.env` template comments endorse for "better
  security"). Round-trip preserves all four
  (`INFLUX_ADMIN_TOKEN` / `INFLUX_TOKEN_READWRITE` / `INFLUX_TOKEN_WRITE`
  / `INFLUX_TOKEN_READ`) as byte-identical copies. `INFLUX_TOKEN_READWRITE`
  is synthesized from the admin token for the (already-present)
  power-splitter — same shape as user13/15/16.
- **Custom non-default InfluxDB bucket name (`my-solectrus-bucket`).**
  Donor's `INFLUX_BUCKET=my-solectrus-bucket` is preserved verbatim;
  every InfluxDB-touching service references it through the bare
  `- INFLUX_BUCKET` passthrough. Differs from default `solectrus`.
- **Nine `INFLUX_SENSOR_CUSTOM_POWER_*` mappings** preserved as
  `custom_power_01..09` sensors with `source: external`, `field: power`,
  and the measurement name pre-filled into the user-label slot
  (`name: TV`, `OVEN`, `OVEN2`, `WA`, `WA2`, `DRYER`, `DRYER2`, `MW`,
  `GSA`). `source: external` (not `shelly`) because the donor's
  shelly-collector measurements never align with the dashboard
  mappings — see _Equivalent on re-export_ below for the case
  mismatch.
- **forecast.solar single-roof config** with anonymized geo (lat/lon
  `0.00000`). Same null-island placeholder as user16 — the importer
  treats lat/lon as opaque strings; `'0.00000'` survives byte-identical.
  `FORECAST_DECLINATION=20`, `FORECAST_AZIMUTH=-45` (signed-negative,
  legacy convention: -45 = SE in the old forecast.solar scale), and
  `FORECAST_KWP=10.0` round-trip into the
  `forecast_declination1` / `forecast_azimuth1` / `forecast_kwp1`
  slots. `FORECAST_INTERVAL=900` preserved at the 15-minute floor for
  the free forecast.solar tier.
- **`FORECAST_SOLAR_APIKEY` preserved** as `forecast.forecast_solar_apikey`
  (paid tier, even though geo is anonymized to `0.0`). HELIOS doesn't
  cross-check whether the key would actually authenticate.
- **`INSTALLATION_DATE=2022-01-01` preserved.** No casing or quoting
  changes.
- **`docker-compose.yml.bak` filename variant — sixth occurrence.**
  Same `Compose::FILENAMES` slot as user3/4/12/16/17; the other three
  slots are covered by user1/2/5/7..11/14/15 (`compose.yaml`),
  user6/10 (`compose.yml`), and user13 (`docker-compose.yaml`).
- **All `*_VOLUME_PATH=./<dir>` bind mounts preserved** (`./influxdb`,
  `./postgresql`, `./redis`). Standard ADR-0003 relative layout.

## Equivalent on re-export (no operational impact)

- **Compose schema `version: "3.7"` top-level literal dropped.** Donor
  declares `version: "3.7"` at the top of `docker-compose.yml.bak`
  (line 1). Modern `docker compose` ignores the field; HELIOS doesn't
  re-emit it. First fixture with an explicit legacy version literal.
- **Nine per-device shelly-collector containers collapsed into one.**
  Donor declares `shelly-collector-tv`, `-gsa`, `-oven`, `-oven2`,
  `-wa`, `-wa2`, `-dryer`, `-dryer2`, `-mw` — nine separate containers
  each pulling `image: ghcr.io/solectrus/shelly-collector:latest`. The
  shelly-collector image natively supports the CSV multi-device shape,
  so HELIOS canonicalizes the fleet into a single container that
  consumes the same eight devices via comma-separated env vars.
  Operationally equivalent (one container reads all eight hosts in
  parallel) but trims `9 × (logging + restart + depends_on + labels +
links)` of compose duplication. The donor-side `restart`/`labels`
  blocks ride through the standard managed-service normalization
  (`unless-stopped`, single `com.centurylinklabs.watchtower.scope=solectrus`
  label).
- **Sensor measurement case mismatch (`TV` vs. `tv`) makes all nine
  `custom_power_*` sensors fall through to `source: external`.** Donor's
  dashboard mapping reads `INFLUX_SENSOR_CUSTOM_POWER_01=TV:power`
  (measurement `TV`, uppercase) while `shelly-collector-tv` writes to
  `INFLUX_MEASUREMENT_SHELLY_TV=tv` (lowercase). InfluxDB measurement
  names are case-sensitive, so the dashboard never sees data the
  collector wrote. HELIOS doesn't second-guess the donor — it captures
  the sensor mapping as-is and tags every custom*power*\* sensor
  `source: external` because no managed-collector measurement aligns.
  Seven of the nine measurement env vars
  (`INFLUX_MEASUREMENT_SHELLY_OVEN`, `_OVEN2`, `_WA`, `_WA2`, `_DRYER`,
  `_DRYER2`, `_MW`) aren't even declared in `.env.bak` at all, so the
  exported CSV `INFLUX_MEASUREMENT=gsa,tv` carries only the two
  donor-defined values; the other six device slots ride through with
  empty measurements (the collector writes to a nameless measurement,
  matching donor behavior).
- **`SHELLY_GEN_*` legacy gen flags dropped wholesale.** Donor sets
  `SHELLY_GEN_TV=2` … `SHELLY_GEN_GSA=2` (nine entries) and references
  them via `SHELLY_GEN=${SHELLY_GEN_<NAME>}` on each per-device
  service. HELIOS's canonical shelly-collector container does not
  surface `SHELLY_GEN` — the modern collector auto-detects the gen
  from the device — so the env vars become unreferenced after the
  multi-device collapse and `unreferenced_in_stack?` drops them. The
  dryer entry was already lost upstream via the lowercase typo (see
  next bullet).
- **`SHELLY_HOST_DRYER=192.168.3.93` dropped (donor-side broken).**
  Donor's compose references `${SHELLY_HOST_dryer}` (lowercase suffix
  on the dryer service, line 207) while `.env.bak` declares
  `SHELLY_HOST_DRYER=192.168.3.93` (uppercase, line 38). Docker
  compose's `${VAR}` interpolation is case-sensitive, so the dryer
  container boots with empty `SHELLY_HOST` and the .env declaration is
  unreferenced. HELIOS's `unreferenced_in_stack?` filter drops it,
  matching donor runtime behavior (the dryer container was already
  inert).
- **`senec-charger` preserved as `_unmanaged.services` with
  `INFLUX_TOKEN=${INFLUX_TOKEN_READ}`.** Donor runs
  `ghcr.io/solectrus/senec-charger:develop` to pulse the SENEC battery
  into grid-charge mode based on Tibber price thresholds
  (`CHARGER_PRICE_TIME_RANGE=4`, `CHARGER_PRICE_MAX=85`,
  `CHARGER_FORECAST_THRESHOLD=10`, `CHARGER_DRY_RUN=false`) and the
  forecast.solar yield (`INFLUX_MEASUREMENT_FORECAST=Forecast`). HELIOS
  emits the service block byte-identical (image, env list, depends_on,
  restart, links). First fixture with `senec-charger` and first fixture
  where an unmanaged SOLECTRUS service binds `INFLUX_TOKEN` to
  `${INFLUX_TOKEN_READ}` rather than `${INFLUX_TOKEN_WRITE}` (it reads
  prices and forecast — both written by other services).
- **`tibber-collector` preserved as `_unmanaged.services`.** Donor runs
  `ghcr.io/solectrus/tibber-collector:develop`, writing
  `INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_PRICES}` (= `Tibber`, a
  non-canonical InfluxDB measurement HELIOS does not manage in the
  sensor registry). `TIBBER_TOKEN` and `TIBBER_INTERVAL` ride through
  via bare env passthrough — both are in `_unmanaged.env_vars`. First
  fixture with `tibber-collector` and the `INFLUX_MEASUREMENT_PRICES`
  slot.
- **`INFLUX_MEASUREMENT_PRICES = Tibber` value-side preserved despite
  whitespace-padded `=` in donor's `.env.bak`.** Donor's `.env.bak`
  has `INFLUX_MEASUREMENT_PRICES = Tibber` (spaces around `=`, line 70),
  same for `CHARGER_INTERVAL = 900`, `CHARGER_PRICE_TIME_RANGE = 4`,
  `CHARGER_PRICE_MAX = 85`, `CHARGER_FORECAST_THRESHOLD = 10`,
  `CHARGER_DRY_RUN = false`, `TIBBER_TOKEN = my-tibber-token`,
  `TIBBER_INTERVAL = 3600`, `TZ = Europe/Berlin`. dotenv strips the
  spaces on read; HELIOS re-emits without surrounding whitespace.
  First fixture with whitespace-padded `=`. Confirms HELIOS follows
  POSIX-shell-compatible parsing despite the upstream `.env` example
  using tight `=`.
- **`INFLUX_EXCLUDE_FROM_HOUSE_POWER` dropped (donor-side broken).**
  Donor's `.env.bak` declares
  `INFLUX_EXCLUDE_FROM_HOUSE_POWER=OVEN_POWER,CUSTOM_POWER_02,OVEN2_POWER,CUSTOM_POWER_03`
  with both naming forms duplicated (OVEN*POWER and CUSTOM_POWER_02
  are the same sensor under two conventions; same for OVEN2). The
  dashboard service's `environment:` list does **not** reference the
  variable, so `service_env('dashboard')['INFLUX_EXCLUDE_FROM_HOUSE_POWER']`
  is nil → `excluded_sensors` is empty → no sensor gets
  `exclude_from_house_power: true` on import. HELIOS suppresses the
  var from `_unmanaged.env_vars` (it's in `MANAGED_ENV_KEYS`), so the
  variable disappears from `.env` entirely. Operationally equivalent
  in the sense that the donor's dashboard never read it either —
  but the donor's \_intent* (exclude OVEN/OVEN2 from house-power) is
  lost. First fixture documenting this dashboard-side reference miss.
- **`DB_HOST=db` rewritten to `DB_HOST=postgresql`.** Donor names the
  postgres service `db` (shorter alias); HELIOS canonicalizes to
  `postgresql`. The `links:` and `depends_on:` blocks follow.
- **InfluxDB explicit `command: influxd run --bolt-path ...
--engine-path ... --store disk` override dropped.** Same
  explicit-defaults override pattern as user7-17.
- **InfluxDB port `8086:8086` not published.** Donor has the line
  commented out (line 353-354 of `docker-compose.yml.bak`). HELIOS
  reads `influxdb.publish_port: false` (default) and omits the
  `ports:` block.
- **`INFLUX_USERNAME=admin` / `INFLUX_PASSWORD=my-influx-password`
  preserved through HELIOS-canonical `INFLUX_PASSWORD` (kept as
  `password` in `config.yaml`).** `INFLUX_USERNAME=admin` is the
  HELIOS default and is dropped from `.env`; the password rides
  through.
- **Power-splitter `INFLUX_TOKEN=${INFLUX_ADMIN_TOKEN}` rewritten to
  `INFLUX_TOKEN=${INFLUX_TOKEN_READWRITE}`.** Donor pointed
  power-splitter directly at the admin token; HELIOS routes it through
  the dedicated read+write slot (auto-synthesized from the admin
  token because donor's `.env.bak` lacks
  `INFLUX_TOKEN_READWRITE`). Same shape as user13/15/16/17.
- **POSTGRES_DB=solectrus / DB_DATABASE=solectrus added.** Donor
  relied on the postgres image's default; HELIOS sets the name
  explicitly. Same as user12-17.
- **Watchtower normalized.** Donor uses `containrrr/watchtower`
  (upstream) with `command: --scope solectrus --cleanup`. HELIOS keeps
  the upstream image (`containrrr/watchtower:latest`) and splits the
  command into env vars (`WATCHTOWER_SCOPE=solectrus`,
  `WATCHTOWER_CLEANUP=true`, plus the default
  `WATCHTOWER_POLL_INTERVAL=86400`).
- **HELIOS service added.** Self-export, test-env only.
- **Restart policies normalized to `unless-stopped` on managed
  services.** Donor mixes `always` (most services) and
  `unless-stopped` (shelly-collectors + power-splitter); HELIOS emits
  `unless-stopped` uniformly across managed services. Unmanaged
  services (`senec-charger`, `tibber-collector`) keep their
  donor-declared `restart: always`.
- **`logging.driver: json-file` added uniformly** across every
  managed service (donor sets logging only on the shelly-collectors
  and power-splitter — both already with `10m`/`3` rotation; HELIOS
  preserves the same rotation limits on the canonical
  shelly-collector container).
- **Healthcheck timings normalized.** Donor's per-service intervals
  (`10s`/`30s`) replaced with HELIOS's canonical
  `interval: 10s` / `timeout: 5s` / `start_interval: 2s`.
- **`INFLUX_POLL_INTERVAL` not set in donor — HELIOS adds the default
  `5`.** Donor's dashboard env block omits the variable entirely
  (not even as a bare reference), and `.env.bak` has no such var.
  HELIOS defaults to `5` and emits it on the dashboard env block plus
  in `.env`. The donor's dashboard was using whatever the SOLECTRUS
  image's compiled-in default is (also 5 today), so no operational
  change.
- **`SENEC_LANGUAGE` not set in donor — HELIOS adds the default
  `de`.** Donor's senec-collector env block does not declare it
  (the senec-collector image defaults to `de`); HELIOS emits the
  default explicitly.
- **`SENEC_ADAPTER=local` added.** Donor's senec-collector image
  (`:develop`) reads the adapter from `SENEC_SCHEMA`/`SENEC_HOST`
  shape; HELIOS emits the explicit `SENEC_ADAPTER` switch.
- **`INFLUX_MEASUREMENT_PV=SENEC` renamed to
  `INFLUX_MEASUREMENT_SENEC=SENEC`.** Donor uses the legacy
  `INFLUX_MEASUREMENT_PV` slot; HELIOS canonicalizes to
  `INFLUX_MEASUREMENT_SENEC`, mirrored by `senec.measurement` if a
  non-default value were used. Same value (`SENEC`), so the senec
  sensors continue to resolve identically.
- **`INFLUX_MEASUREMENT_FORECAST=Forecast` collapsed.** Donor sets it
  both on the dashboard (`- INFLUX_MEASUREMENT_FORECAST`) and on
  forecast-collector / senec-charger
  (`- INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_FORECAST}`). HELIOS
  emits the single canonical declaration and re-uses
  `${INFLUX_MEASUREMENT_FORECAST}` indirection where needed (kept on
  the unmanaged senec-charger service block).
- **`name: solectrus` and `networks.default.name: solectrus_default`
  added.** Donor has neither (no top-level `name:`, no `networks:`).
- **`links:` blocks dropped on managed services.** Donor uses
  `links: [influxdb]` etc., which compose treats as a legacy
  service-discovery hint. HELIOS uses `depends_on:` exclusively and
  drops the `links:` block from managed services. Unmanaged services
  (`senec-charger`, `tibber-collector`) keep their donor-declared
  `links:` byte-identical.
- **Sensor reordering on export.** Donor's `INFLUX_SENSOR_*` block in
  `.env.bak` lists only the nine `CUSTOM_POWER_*` mappings; HELIOS
  re-emits them under the canonical sensor block order
  (inverter*power, grid*\_, battery\_\_, wallbox_power, case_temp,
  system_status\*, inverter_power_forecast, custom_power_01..09) and
  prefixes each with a `# Sensor: <name>` comment.
