# user13

Real-world `docker-compose.yaml` + `.env` from a SOLECTRUS user running
a **local-adapter SENEC V3** (three MPPTs) with `power-splitter`,
`watchtower`, and nothing else — no Shelly, no forecast, no MQTT, no
heat pump. The donor leaves the upstream `.env` template fully
populated: every placeholder slot (`INVERTER_POWER_4/_5`, all 20
`CUSTOM_POWER_*`, heatpump + outdoor + car SoC + forecast) is declared
but **empty**, and every cloud-SENEC credential
(`SENEC_USERNAME`/`_PASSWORD`/`_TOTP_URI`/`_SYSTEM_ID`/`_IGNORE`) sits
commented out. The compose's collector `environment:` blocks still
list them all as bare passthroughs, so at runtime they are unset
references the importer must distinguish from genuine values. The
fixture also exercises the **third filename variant** in
`Compose::FILENAMES` and the **admin-token-via-`INFLUX_TOKEN`
shortcut** for power-splitter. Anonymized but otherwise untouched.

## Imported correctly (round-trip preserves the value)

- **Remapped dashboard host port `3010:3000` preserved.** Donor maps
  the dashboard container's port `3000` to host port `3010` — most
  likely because something else (a host-level service, another stack)
  already occupies `3000`. Earlier HELIOS revisions hardcoded
  `3000:3000` on export, silently breaking the donor's port choice
  and any reverse-proxy rule pointing at `:3010`. The donor's value is
  now captured into the new `dashboard.host_port` round-trip field
  (no UI yet, same shape as `influx_poll_interval`) and re-emitted
  verbatim in the compose `ports:` block. First fixture exercising
  a non-default dashboard host port.
- **`docker-compose.yaml.bak` filename variant — third of four
  supported.** user6 covered `compose.yml`, user3/user4/user12 covered
  `docker-compose.yml`, user1/user2/user5/user7..user11 covered the
  canonical `compose.yaml`. user13 fills the last slot in
  `Compose::FILENAMES` (`compose.yaml`, `compose.yml`,
  `docker-compose.yaml`, `docker-compose.yml`): the `.yaml` extension
  with the `docker-compose` prefix that some templating tools still
  emit. `compose_backup_path` resolves it lazily, importer succeeds.
- **Three-MPPT SENEC V3 with no balcony heuristic trip.** Donor maps
  `INFLUX_SENSOR_INVERTER_POWER_1/_2/_3=SENEC:mpp1/mpp2/mpp3_power` —
  all three slots share the `SENEC:` measurement. Same shape as
  user5/user7 (also SENEC V3 three-string); measurement-divergence
  heuristic correctly keeps `is_balcony: false` because no slot
  diverges from the others.
- **Empty `INVERTER_POWER_4=` / `_5=` template slots dropped.** Donor
  declares the placeholder slots both in `.env` (`=`-only) and in the
  dashboard `environment:` block (`- INFLUX_SENSOR_INVERTER_POWER_4`).
  `SensorsExtractor#well_formed_mapping?` rejects the empty values; on
  re-export neither slot appears in `config.yaml`, `.env`, or the
  dashboard env list. Same drop-on-empty path that catches user12's
  unused `CUSTOM_POWER` slots, but applied to inverter MPPT slots
  (relevant because the upstream template ships five slots and
  three-MPPT installs leak two empties).
- **All 20 `CUSTOM_POWER_01..20` template slots dropped.** Donor has
  no Shelly, no MQTT, no custom appliances — every `CUSTOM_POWER_*`
  line is `=`-only. None survive to `config.yaml` or the re-exported
  `.env`. Same mechanism as the `INVERTER_POWER_4/_5` drop above and
  user12's empty slots; differs from user12 by having **zero** active
  custom slots (user12 has six).
- **Heatpump + outdoor + car-SoC + forecast template slots dropped.**
  Donor `.env` declares
  `INFLUX_SENSOR_HEATPUMP_POWER=`, `_HEATING_POWER=`, `_TANK_TEMP=`,
  `_STATUS=`, `INFLUX_SENSOR_OUTDOOR_TEMP=`, `_FORECAST=`,
  `INFLUX_SENSOR_CAR_BATTERY_SOC=`,
  `INFLUX_SENSOR_INVERTER_POWER_FORECAST=`,
  `INFLUX_SENSOR_INVERTER_POWER_FORECAST_CLEARSKY=` — all empty.
  Compose env block lists most of them too (as bare passthroughs). All
  drop on re-export; no empty stubs leak through. Confirms the
  upstream-template-defaults shape round-trips cleanly even when the
  donor has wired no peripherals.
- **Power-splitter wired via `INFLUX_TOKEN=${INFLUX_ADMIN_TOKEN}`.**
  Donor takes the documented-but-permissive shortcut: instead of
  splitting permissions, the power-splitter uses the admin token
  directly through its `INFLUX_TOKEN` env var. HELIOS normalizes to
  `INFLUX_TOKEN=${INFLUX_TOKEN_READWRITE}` on export and synthesizes
  `INFLUX_TOKEN_READWRITE=my-super-secret-admin-token` in `.env`
  (admin-token value carried through, but the canonical
  per-permission-role variable name now used). Confirms HELIOS's
  token-fallback chain resolves admin → readwrite without leaking the
  admin token reference into export.
- **`INFLUX_TOKEN_WRITE=INFLUX_TOKEN_READ=INFLUX_ADMIN_TOKEN` all set
  to the same value.** Donor follows the documented "local/internal
  use" simplification: all three tokens carry
  `my-super-secret-admin-token` (the comment in `.env` explicitly
  endorses this). Round-trip keeps all three byte-identical and adds
  the new `INFLUX_TOKEN_READWRITE` set to the same value. Confirms the
  fallback chain doesn't collapse duplicate values into a single var.
- **SENEC local adapter with cloud credentials fully commented out.**
  Donor uses `SENEC_ADAPTER=local`, `SENEC_HOST=192.168.1.211`,
  `SENEC_SCHEMA=https`, `SENEC_LANGUAGE=de`, `SENEC_INTERVAL=5` —
  every cloud var (`SENEC_USERNAME`, `SENEC_PASSWORD`,
  `SENEC_TOTP_URI`, `SENEC_SYSTEM_ID`) is `# `-prefixed in `.env`. The
  senec-collector compose env block still lists them as bare
  passthroughs (`- SENEC_PASSWORD`, etc.). Importer reads adapter from
  `.env`, resolves the four cloud vars as unset, drops them entirely
  on re-export — neither the env file nor the senec-collector env
  block carries them forward. Same shape `senec.adapter: local` as
  user4/user12 but with the full cloud-template-as-comments left in
  place.
- **`INFLUX_MEASUREMENT_SENEC=SENEC` preserved.** Donor's senec-
  collector env uses the indirection
  `INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_SENEC}` (the older upstream
  template style); HELIOS simplifies on export to a direct
  `INFLUX_MEASUREMENT_SENEC` passthrough, but the measurement string
  itself stays `SENEC`. Same canonicalization as user12, with the
  indirection collapsed to the canonical per-collector name.
- **Watchtower `nickfedor/watchtower` (no tag) → `:latest`, command
  → env vars.** Donor runs the fork with bare
  `command: --scope solectrus --cleanup`; HELIOS canonicalizes to
  `nickfedor/watchtower:latest` and splits the command into
  `WATCHTOWER_SCOPE=solectrus` / `WATCHTOWER_CLEANUP=true`, adds the
  default `WATCHTOWER_POLL_INTERVAL=86400`. Same path as user6/user12.
- **`POSTGRES_PASSWORD` and `DB_PASSWORD=${POSTGRES_PASSWORD}` shape
  preserved.** Donor wires it through explicitly on both dashboard and
  power-splitter; round-trip keeps the indirection.
- **`INSTALLATION_DATE=2020-01-01` preserved as `'2020-01-01'`.**
  Six-year-old install date round-trips as a quoted ISO string — same
  as user11/user12 but with an older year, confirming
  `Configuration.dump` doesn't quirk on different decades.
- **`APP_HOST=192.168.1.216` (raw IPv4) preserved.** Donor reaches the
  dashboard by IP rather than DNS name; importer doesn't try to
  hostname-rewrite. Same shape as user12's IP, different host octet.
- **Volume paths preserved.** `INFLUX_VOLUME_PATH=./influxdb`,
  `DB_VOLUME_PATH=./postgresql`, `REDIS_VOLUME_PATH=./redis` — donor
  uses the canonical ADR-0003 relative-path layout; round-trip
  passes them through unchanged.
- **Modern image baseline preserved.** `postgres:18-alpine`,
  `redis:8-alpine`, `influxdb:2-alpine`,
  `ghcr.io/solectrus/solectrus:latest` — donor is already on the
  current major versions HELIOS would otherwise emit as defaults. No
  upgrade nudge, no downgrade nudge, byte-identical image tags on
  re-export.

## Equivalent on re-export (no operational impact)

These look like changes in the diff but don't alter what the stack
actually does — HELIOS's defaults match the donor's explicit values,
the value is simply re-spelled, or the var was already dead at runtime.

- **`links: - influxdb` blocks dropped from senec-collector and
  power-splitter.** Legacy compose feature; modern bridge-network
  service discovery makes it a no-op. Same as user12.
- **InfluxDB `command: influxd run --bolt-path ... --engine-path ...
  --store disk` dropped.** Donor sets the InfluxDB 2.x image defaults
  explicitly; HELIOS drops the redundant override (same as
  user7/user8/user9/user10/user11/user12).
- **InfluxDB UI port stays unpublished.** Donor doesn't expose 8086;
  import captures no `influxdb.publish_port` flag, and re-export
  emits no `ports:` block on `influxdb`. Same as user11/user12.
- **`INFLUX_HOST=influxdb` / `INFLUX_PORT=8086` / `INFLUX_SCHEMA=http`
  / `INFLUX_USERNAME=admin` dropped from `.env`.** HELIOS bakes these
  into compose service-network addressing and hardcodes the admin
  username (same as user10/user11/user12). Donor used the documented
  defaults, so a fresh init against an empty volume produces identical
  credentials.
- **Empty `FRAME_ANCESTORS` / `UI_THEME` / `CO2_EMISSION_FACTOR`
  passthroughs dropped from dashboard env.** Donor lists them as bare
  references (`- FRAME_ANCESTORS`, `- UI_THEME`, `- CO2_EMISSION_FACTOR`)
  but never sets values in `.env` (the template-comment forms remain
  `# `-prefixed). At runtime these were unset references; HELIOS drops
  the dead env lines.
- **Empty `REDIS_URL` passthrough → inline `REDIS_URL=redis://redis:6379/1`.**
  Donor wires the dashboard via `- REDIS_URL` and defines
  `REDIS_URL=redis://redis:6379/1` in `.env`; HELIOS inlines the
  literal directly in the dashboard/power-splitter env blocks and
  drops the `.env` entry. Same shape as user12.
- **`SENEC_TOTP_URI` / `SENEC_USERNAME` / `SENEC_PASSWORD` /
  `SENEC_SYSTEM_ID` / `SENEC_IGNORE` env passthroughs dropped from
  senec-collector.** Donor's senec-collector env block still lists
  all five even though `.env` has them commented out. HELIOS strips
  the dead references; only the active local-adapter vars survive.
- **`INFLUX_SCHEMA` / `INFLUX_PORT` dropped from senec-collector and
  power-splitter env.** Donor passes them through (`- INFLUX_SCHEMA`,
  `- INFLUX_PORT`); HELIOS bakes the connection into the in-network
  default `http://influxdb:8086` and drops the env lines.
- **`POWER_SPLITTER_INTERVAL=3600` emitted (donor had it commented).**
  Donor's `.env` leaves the var as `# POWER_SPLITTER_INTERVAL=3600`,
  so at runtime the collector falls back to its built-in default
  (also `3600`). HELIOS emits the documented default explicitly.
- **`POSTGRES_DB=solectrus` / `DB_DATABASE=solectrus` added.** Donor
  relied on the postgres image default (also `solectrus`); HELIOS
  sets the name explicitly. Same as user12.
- **`POSTGRES_PASSWORD` plain passthrough added to power-splitter
  env.** Donor only wires `DB_PASSWORD=${POSTGRES_PASSWORD}`; HELIOS
  adds the raw `POSTGRES_PASSWORD` passthrough too (the power-splitter
  reads both names; bare reference is harmless).
- **`name: solectrus` and `networks.default.name: solectrus_default`
  added.** Donor compose has neither (relies on the implicit project
  name from the directory).
- **HELIOS service added.** Self-export.
- **Healthcheck timings normalized.** Donor's `interval: 30s|10s` /
  `timeout: 10s|20s` / `start_period: 10s|30s|60s` replaced with
  HELIOS's standard intervals (`interval: 10s` / `timeout: 5s` plus a
  `start_interval: 2s`). Same probes, faster startup feedback.
- **Sensor reordering on export.** Donor lists sensors in the upstream
  template's loose grouping; export sorts sensors alphabetically
  inside `config.yaml` and renders `.env` in HELIOS's canonical block
  order (general → security → dashboard → DBs → cache → power-splitter
  → senec → watchtower → sensors).
