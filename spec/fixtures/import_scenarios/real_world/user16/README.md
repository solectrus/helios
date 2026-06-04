# user16

Real-world `docker-compose.yml.bak` + `.env` from a SOLECTRUS user
running a **local-adapter SENEC V3** on a **Raspberry Pi** host
(`/home/pi/solectrus/...` volume layout), with a **two-roof pvnode
(paid) forecast** and `watchtower`. No power-splitter in the donor
stack, no Shelly, no MQTT, no heat pump — a deliberately stripped-down
SENEC-only setup with `dozzle` tacked on as the only unmanaged extra.
The fixture exercises four quirks no prior fixture covers: a **sparse
MPPT mapping** (slots `_1` and `_3` set, `_2` empty between them), a
**duplicate `INFLUX_MEASUREMENT_FORECAST` declaration with mismatched
casing** (`Forecast` then `forecast` — dotenv last-write-wins resolves
to lowercase), an **inline `INFLUX_SENSOR_*=forecast:watt_clearsky`
literal in `forecast-collector`'s compose env list** (a dead reference
the collector never reads), and a **nonsensical `FORECAST_INTERVAL=2`
for a pvnode stack** (pvnode ignores the variable per the upstream
docs — importer drops it from `config.yaml`, exporter omits it
entirely). Anonymized but otherwise untouched.

## Imported correctly (round-trip preserves the value)

- **Sparse MPPT mapping: slots `_1` and `_3` populated, `_2` empty
  between them.** Donor's `.env` sets
  `INFLUX_SENSOR_INVERTER_POWER_1=SENEC:mpp1_power` and
  `INFLUX_SENSOR_INVERTER_POWER_3=SENEC:mpp3_power`, leaves
  `_2=` / `_4=` / `_5=` empty. The two populated slots survive as
  separate `inverter_power_1` / `inverter_power_3` sensors; the three
  empty slots drop via `well_formed_mapping?`. First fixture with a
  **non-contiguous** MPPT mapping — different from user11 (all five
  empty, no slots survive) and user13/15 (`_1/_2/_3` populated,
  `_4/_5` empty). Confirms the importer treats each slot
  independently and doesn't collapse on a missing intermediate.
- **`docker-compose.yml.bak` filename variant — second of four.** Same
  slot in `Compose::FILENAMES` as user3/4/12; the other three slots
  (`compose.yaml`, `compose.yml`, `docker-compose.yaml`) are covered
  by user1/2/5/7..11/13..15, user6, and user13 respectively.
- **`PVNODE_PAID=true` (lowercase) two-roof pvnode forecast.** Same
  shape as user15: `FORECAST_PROVIDER=pvnode`, `PVNODE_APIKEY` set,
  `PVNODE_PAID=true` lowercase. Two roofs at 30°/6.4 kWp / azimuth
  158° (SSE) and 30°/2.2 kWp / azimuth 338° (NNW). All plane fields
  round-trip as strings; `forecast.forecast_pvnode_paid: 'true'`
  preserves the lowercase casing verbatim (forecast-collector accepts
  either form).
- **`FORECAST_LATITUDE=0.00000` / `FORECAST_LONGITUDE=0.00000`
  placeholder geo preserved.** Donor anonymized the coordinates to
  the null island; HELIOS treats them as opaque strings and re-emits
  `'0.00000'` (string-quoted, five-decimal precision). First fixture
  with placeholder geo — confirms the importer doesn't validate or
  normalize latitude/longitude.
- **Single-token simplification (`INFLUX_TOKEN_WRITE` /
  `INFLUX_TOKEN_READ` / `INFLUX_ADMIN_TOKEN` all
  `my-super-secret-admin-token`).** Donor follows the "local/internal
  use" shortcut endorsed by the upstream `.env` template comments
  (lines 44-45). Round-trip keeps all three byte-identical and adds
  `INFLUX_TOKEN_READWRITE` (auto-synthesized from the admin token for
  the auto-added power-splitter — see *Equivalent on re-export*).
  Same shape as user13/15.
- **Watchtower `nickfedor/watchtower:latest` with `command` split to
  env vars.** Donor runs the `nickfedor/` fork (same as user13/14)
  and passes `command: --scope solectrus --cleanup`. HELIOS splits to
  `WATCHTOWER_SCOPE=solectrus` / `WATCHTOWER_CLEANUP=true`, plus the
  default `WATCHTOWER_POLL_INTERVAL=86400`.
- **`/home/pi/solectrus/<service>` Raspberry Pi volume layout
  preserved.** Donor mounts the three `${X_VOLUME_PATH}` envs to
  absolute Pi-home paths. Round-trip passes them through verbatim
  (HELIOS doesn't rewrite to the ADR-0003 relative layout).
- **InfluxDB UI port `8086:8086` published.** Donor exposes 8086
  (the inline comment in `docker-compose.yml.bak` line 70 endorses
  it as "optional"). HELIOS captures `influxdb.publish_port: true`
  and re-emits the `ports:` block.
- **`influxdb:2.7-alpine`, `postgres:16-alpine`, `redis:7-alpine`
  pinned older tags preserved.** Donor pins each one to a minor
  version one or two majors behind HELIOS's emit defaults
  (post-`develop` 580168a7 bumped the default to
  `influxdb:2.9-alpine`). Round-trip keeps the donor's tags
  byte-identical (HELIOS doesn't upgrade-nudge).

## Equivalent on re-export (no operational impact)

- **`FORECAST_INTERVAL=2` dropped entirely for pvnode.** Donor set the
  interval to `2` (likely a typo); pvnode ignores the variable at
  runtime per the upstream docs. Importer drops it from `config.yaml`,
  exporter omits it from `.env` and from the `forecast-collector` env
  passthrough.
- **Duplicate `INFLUX_MEASUREMENT_FORECAST` collapsed
  (last-write-wins).** Donor declares the var twice with mismatched
  casing — line 42 `=Forecast` (capitalized), line 60 `=forecast`
  (lowercase). dotenv applies last-write-wins; HELIOS emits a single
  canonical `INFLUX_MEASUREMENT_FORECAST=forecast` (the lowercase
  survivor) in `.env`, mirrored by
  `config.yaml.forecast.measurement: forecast`. Differs from user4's
  pair-of-identical duplicates — user16 is the first fixture with
  **mismatched-value** duplicates, confirming the importer follows
  dotenv semantics rather than first-wins or warning-on-conflict.
- **Inline `INFLUX_SENSOR_INVERTER_POWER_FORECAST_CLEARSKY=forecast:watt_clearsky`
  in `forecast-collector` compose env dropped.** Donor sets the
  literal inline (line 194 of `docker-compose.yml.bak`) alongside the
  bare `INFLUX_SENSOR_OUTDOOR_TEMP_FORECAST` passthrough. The
  collector writes forecast data and never reads sensor mappings —
  both lines are dead references at runtime. HELIOS drops them from
  the re-exported forecast-collector env block; the same sensor
  values remain active on the dashboard and power-splitter where they
  belong. First fixture with an **inline sensor literal placed on the
  writer service** rather than the reader.
- **Power-splitter service added.** Donor compose has no
  `power-splitter`; HELIOS adds it as a managed service with a fixed
  `POWER_SPLITTER_INTERVAL=300` (5-minute cadence) and synthesizes
  `INFLUX_TOKEN_READWRITE` from the donor's existing admin token.
  Same auto-add as user10/12.
- **Legacy `# version: '3.7'` header comment dropped.** Donor leaves
  the long-deprecated `version` pragma as a commented header. HELIOS
  emits its own canonical header block; the legacy line goes away.
  Same shape as user1's `#version: '3.7'`, user4's `## version: '3.7'`,
  and user12's uncommented `version: '3.7'`.
- **Inline German comment `# Extra Sensoren PV Node` dropped from
  dashboard env list.** Donor wedges a German section marker (line 44)
  between `INFLUX_SENSOR_INVERTER_POWER_5` and
  `INFLUX_SENSOR_OUTDOOR_TEMP_FORECAST` in the dashboard
  `environment:` block. Comments inside `compose.yaml` are not
  preserved (CLAUDE.md "Project-Specific Rules"); HELIOS's
  alphabetical re-ordering of the env block strips it.
- **`links: - db, influxdb, redis` blocks dropped from dashboard and
  every collector.** Legacy compose feature; modern bridge-network
  service discovery makes them no-ops. Same as user12/13/14/15.
- **InfluxDB `command: influxd run --bolt-path ... --engine-path ...
  --store disk` dropped.** Donor's explicit-defaults override removed
  (same as user7-15).
- **`INFLUX_HOST=influxdb` / `INFLUX_SCHEMA=http` / `INFLUX_PORT=8086`
  / `INFLUX_USERNAME=admin` dropped from `.env`.** HELIOS bakes the
  connection into compose service-network addressing and hardcodes
  the admin username on export. Donor's `INFLUX_USERNAME=admin`
  already matches HELIOS's canonical value — only the redundant
  variable presence changes.
- **`INFLUX_SCHEMA` / `INFLUX_PORT` dropped from collector env.**
  Donor passes them through as bare passthroughs; HELIOS bakes the
  in-network default `http://influxdb:8086`. Same as user13/14/15.
- **`REDIS_URL=redis://redis:6379/1` kept inline.** Donor already
  inlines it on the dashboard `environment:` block (line 30); HELIOS
  preserves it inline on dashboard and propagates the same inline
  literal to the auto-added power-splitter. Same shape as user12-15.
- **`INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_PV}` indirection
  canonicalized to `INFLUX_MEASUREMENT_SENEC`.** Donor's senec-collector
  env block uses the PV-named indirection (line 143); HELIOS rewrites
  the senec-collector to a bare `INFLUX_MEASUREMENT_SENEC` passthrough
  and writes `INFLUX_MEASUREMENT_SENEC=SENEC` in `.env`. Same
  canonicalization as user12-15.
- **`INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_FORECAST}` indirection
  preserved.** Donor's forecast-collector keeps the forecast-named
  indirection (line 205); HELIOS preserves it unchanged.
- **`POSTGRES_DB=solectrus` / `DB_DATABASE=solectrus` added.** Donor
  relied on the postgres image default (also `solectrus`); HELIOS
  sets the name explicitly. Same as user12-15.
- **`POSTGRES_PASSWORD` plain passthrough added to power-splitter
  env.** HELIOS-canonical alongside `DB_PASSWORD=${POSTGRES_PASSWORD}`.
- **`WEB_CONCURRENCY=0` emitted explicitly.** Donor doesn't set it;
  HELIOS adds the documented default (single-process Puma).
- **Upstream-template documentation comments stripped.** Donor's
  `.env.bak` lines 88-101 and 138-174 carry the upstream forecast.solar
  template (lat/long/declination/azimuth/kwp/damping examples) plus
  its description of the multi-plane configuration layout. None is
  active. HELIOS emits clean per-block headers without the donor's
  residual template comments. Same hygiene as user13-15.
- **`restart: always` → `restart: unless-stopped` on five services.**
  Donor mixes restart policies: `always` on dashboard / influxdb /
  postgresql / redis / senec-collector, `unless-stopped` on the rest.
  HELIOS normalizes every managed service to `unless-stopped`. Same
  process-lifecycle semantics in practice — operator-initiated stops
  are honored in both.
- **`logging.driver: json-file` added uniformly.** Donor only sets
  the driver explicitly on `forecast-collector` (line 209); the
  other seven services rely on the docker daemon default. HELIOS
  normalizes every service to the same explicit `json-file` driver.
  Same lines captured, consistent layout.
- **`name: solectrus` and `networks.default.name: solectrus_default`
  added.** Donor has neither.
- **HELIOS service added.** Self-export.
- **Healthcheck timings normalized.** Donor's per-service intervals
  (`30s` / `10s`) and start-periods (`30s` / `60s`) replaced with
  HELIOS's standard `interval: 10s` / `timeout: 5s` / `start_interval:
  2s`. Same probes, faster startup feedback.
- **`dozzle` preserved as unmanaged service.** Donor's
  `amir20/dozzle:latest` log-viewer with port `8080:8080` and the
  watchtower scope label survives the round-trip under `_unmanaged`.
- **Sensor reordering on export.** Donor groups sensors loosely;
  export sorts sensors alphabetically in `config.yaml` and renders
  `.env` in HELIOS's canonical block order.
