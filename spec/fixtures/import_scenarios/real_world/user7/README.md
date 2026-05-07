# user7

Real-world `compose.yaml` + `.env` from a SOLECTRUS user running an evcc-fed
stack: there is **no native SENEC collector** — every live value enters
InfluxDB through the MQTT collector, sourced from evcc and a handful of
hassio bridge topics. SENEC V3 with three MPPTs (`mpp1`/`mpp2`/`mpp3`),
single-roof pvnode forecast, no Traefik (port 3000 published directly),
27-slot MQTT mapping table with mixed German/English commentary and
several commented-out alternatives. Anonymized but otherwise untouched.

## Imported correctly (round-trip preserves the value)

- **evcc-only data path** — no SENEC collector service in the stack;
  every dashboard sensor (`inverter_power`, `house_power`,
  `grid_import_power`/`_export_power`, `battery_charging`/`_discharging`,
  `battery_soc`, `wallbox_power`, `wallbox_car_connected`,
  `heatpump_power`) gets `source: mqtt` with the donor's evcc topic
  attached. First fixture exercising this fully MQTT-driven shape.
- **Three-MPPT SENEC** — `INFLUX_SENSOR_INVERTER_POWER_1/2/3=mpp1/mpp2/mpp3`
  round-trip as `inverter_power_1/2/3` with `source: external`. user6
  exercised two MPPTs; user7 covers the contiguous-three case.
- **Signed-split MQTT mappings consolidated to formula form.** Donor
  uses `MAPPING_2` (grid) and `MAPPING_3` (battery) with
  `_MEASUREMENT_POSITIVE`/`_NEGATIVE` and `_FIELD_POSITIVE`/`_NEGATIVE`
  pairs. Importer splits each into two sensors with directional
  `mqtt_formula` values (`IF({value} > 0, {value}, 0)` and
  `IF({value} < 0, -{value}, 0)`); export re-emits as four plain
  `MAPPING_*` blocks pointing at the same topic. Same shape user1
  exercises, but here it covers both grid and battery in one fixture.
- **Battery sign convention preserved.** Donor's
  `MAPPING_3_FIELD_POSITIVE=bat_power_minus` /
  `_FIELD_NEGATIVE=bat_power_plus` reflects evcc semantics (positive
  payload = battery discharging). Round-trip keeps the formulas
  consistent so charging power still ends up in `bat_power_plus` and
  discharging in `bat_power_minus`.
- **27 mapping slots, 9 commented out.** Donor numbers
  `MAPPING_0..MAPPING_26` with `MAPPING_7/8/12/16/17/18/19/23/24`
  commented out. Importer ignores the comment-marked blocks and pulls
  in the live 18; re-export renumbers them `0..19` (managed sensors)
  plus two trailing "additional" slots for the unmanaged
  `hassio/senec/co2` and `hassio/opel/mileage` topics that have no
  matching managed sensor.
- **Trailing whitespace on env values.** Donor leaves stray spaces
  after `MAPPING_16..26_TYPE=` lines (e.g. `MAPPING_16_TYPE=integer  `
  with two trailing spaces). The env parser strips them, so the
  imported `type` values are clean `integer`/`float`/`string`.
- **Watchtower fork command transformed.** Donor uses
  `nickfedor/watchtower` with `command: --scope solectrus --cleanup`;
  HELIOS recognizes the fork, drops the `command:` override, and emits
  `WATCHTOWER_SCOPE=solectrus` + `WATCHTOWER_CLEANUP=true` in `.env`.
- **20 referenced custom-power slots.** `INFLUX_SENSOR_CUSTOM_POWER_01..20`
  are all present in the dashboard env list. Slots 01..07 alias real
  SENEC fields (`trockner`, `waschmaschine`, `gefrierschrank`,
  `itdach`, `kuehlschrank`, `spuelmaschine`, `fernseher`); slots
  08..20 reference dead measurements (`custom_NN:power`). All 20
  round-trip — 01/02/04/05/06 with their MQTT topic attached, 03/07
  and 08..20 as `source: external`.
- **Mixed German/English comments stripped.** Donor mixes
  `# Anbieter` / `# Zeitzone` / `# Standort` / `# Anzahl der Dachflächen`
  / `# Erste Dachfläche` with English headers. Comments don't survive
  re-export (HELIOS owns its own comment templates), but no value is
  lost.
- **Duplicate `TZ=Europe/Berlin`** — declared once in the General
  block and again under `# Zeitzone` in the forecast block. Env parser
  dedupes (last-wins, identical values, no impact).
- **`INFLUX_MEASUREMENT_FORECAST=forecast`** — preserved as
  `forecast.measurement: forecast`.
- **`POWER_SPLITTER_INTERVAL=300`** — inlined into the power-splitter
  service's `environment:` block (same as user3..user6).
- **Three identical InfluxDB tokens consolidated.**
  `INFLUX_ADMIN_TOKEN`, `INFLUX_TOKEN_WRITE`, `INFLUX_TOKEN_READ` all
  hold the same anonymized value, so the donor's per-service
  `INFLUX_TOKEN=${INFLUX_TOKEN_READ}` / `=${INFLUX_TOKEN_WRITE}` /
  `=${INFLUX_ADMIN_TOKEN}` overrides all collapse to a single
  `INFLUX_TOKEN` losslessly (same shape as user6).
- **Dashboard published on `3000:3000` without Traefik.** Same shape
  as user1/user3/user4: dashboard ports survive, no `reverse_proxy.*`
  section is created, `FORCE_SSL=false` and `APP_HOST=192.168.178.114`
  (literal IP) round-trip.
- **`FRAME_ANCESTORS=*`** — wildcard kept verbatim under
  `dashboard.frame_ancestors`.
- **Single-roof forecast values declared with per-roof prefix.** Donor
  pairs `FORECAST_CONFIGURATIONS=1` with prefixed
  `FORECAST_0_DECLINATION=30` / `FORECAST_0_AZIMUTH=180` /
  `FORECAST_0_KWP=9.72` instead of the unprefixed slots HELIOS emits.
  `ForecastExtractor#single_roof_data` falls back to the
  `FORECAST_0_*` values when the unprefixed ones are missing, so the
  values land in `forecast_declination1` / `forecast_pvnode_azimuth1`
  / `forecast_kwp1` and re-emit losslessly under the unprefixed names.
  Symmetric to the global-→-per-roof fallback the multi-roof path
  added for user6.

## Equivalent on re-export (no operational impact)

These look like changes in the diff but don't alter what the stack
actually does — HELIOS's defaults match the donor's explicit values,
or the value is simply re-spelled.

- **`INFLUX_PORT=8086` / `INFLUX_SCHEMA=http` / `INFLUX_HOST=influxdb`
  dropped** — HELIOS bakes these into compose service-network
  addressing for dashboard, mqtt-collector, forecast-collector, and
  power-splitter, so the runtime endpoint is unchanged.
- **`INFLUX_USERNAME=XXX` dropped.** HELIOS initializes with the
  default `solectrus` username; harmless against an already-initialized
  volume.
- **`INFLUX_MEASUREMENT=SENEC` dropped.** Per-mapping
  `MAPPING_*_MEASUREMENT` entries already carry the measurement name,
  so the global default has no effect on the running stack.
- **InfluxDB `command:` override dropped.** Donor spelled out
  `influxd run --bolt-path /var/lib/influxdb2/influxd.bolt --engine-path
  /var/lib/influxdb2/engine --store disk` — these are the InfluxDB 2.x
  defaults, identical behavior under the image default.
- **Inline literal `INFLUX_TOKEN=${INFLUX_TOKEN_READ/WRITE/ADMIN_TOKEN}`**
  rewritten to plain `INFLUX_TOKEN`, pulling from the consolidated
  value above.
- **Custom-power slots `_08..20` referenced but undefined.** Already
  dead refs in the donor (`environment:` lists them, no measurement
  exists); silent drop matches what the running stack saw.
- **`mqtt-collector` `restart: always` normalized to
  `unless-stopped`.** Donor's only outlier in restart policy; HELIOS's
  uniform `unless-stopped` covers the same operational intent.
- **Single-quoted Watchtower scope labels normalized.** Donor mixes
  `'com.centurylinklabs.watchtower.scope=solectrus'` (forecast-collector,
  mqtt-collector) with unquoted form; HELIOS emits unquoted everywhere.
- **`links: - influxdb` (legacy) dropped** from forecast-collector and
  mqtt-collector. Compose v2 ignores `links` for service-network
  resolution; HELIOS doesn't re-emit it.
- **Healthcheck timings normalized.** Donor's `interval: 30s` /
  `timeout: 10s` / `start_period: 30s|60s` replaced with HELIOS's
  shorter standard intervals (`interval: 10s` / `timeout: 5s` plus a
  `start_interval: 2s`). Same probes, faster startup.
- **Dashboard `WEB_CONCURRENCY=0`** moved from a literal `.env` value
  into a baked-in compose default (HELIOS treats `0` as the default,
  so the env var disappears from `.env` while the runtime value stays
  the same).
- **Commented-out optional vars discarded.** `# RAILS_MAX_THREADS=3`,
  `# RAILS_LOG_LEVEL=info`, `# ASSET_HOST=`, `# CO2_EMISSION_FACTOR=401`,
  `# UI_THEME=`, `#LOCKUP_CODEWORD=S0170d7s!` (no space after `#`),
  `# SKIP_BROWSER_CHECK=true`, `# HONEYBADGER_API_KEY=`,
  `# RORVSWILD_API_KEY=`, `# PLAUSIBLE_URL=`,
  `#INFLUX_EXCLUDE_FROM_HOUSE_POWER=HEATPUMP_POWER` — none active in
  the donor stack, all correctly ignored. The `#LOCKUP_CODEWORD` line
  in particular has no space after `#`, confirming the comment parser
  treats it as a comment regardless of spacing.
- **Empty `INFLUX_SENSOR_INVERTER_POWER_4=` / `_5=`** — donor reserves
  but doesn't fill MPPT slots 4 and 5; importer correctly leaves them
  unset rather than emitting empty sensors.
