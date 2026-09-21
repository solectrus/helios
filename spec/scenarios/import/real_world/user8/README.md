# user8

Real-world `compose.yaml` + `.env` from a SOLECTRUS user driving the stack
entirely from an **Enphase Envoy gateway** plus a **Daikin Altherma heat
pump via espaltherma**, both proxied through MQTT (no native SENEC
collector). Three-MPPT array (East/South/West) with per-string
`forSOLECTRUS/pv_*` topics, ten Shelly-monitored appliances, and three
distinct InfluxDB tokens. Anonymized but otherwise untouched.

## Imported correctly (round-trip preserves the value)

- **Single-topic Envoy fanout — four sensors from one
  `envoy/json` payload.** First fixture exercising the full Enphase
  pattern: one MQTT topic produces `inverter_power`
  (`MAPPING_0_JSON_FORMULA=round({$.meters.pv.agg_p_mw} / 1000)`),
  signed-split `grid_import_power`/`grid_export_power` (`MAPPING_2`,
  `meters.grid.agg_p_mw`), signed-split `battery_charging_power`/
  `battery_discharging_power` (`MAPPING_3`, `meters.storage.agg_p_mw`),
  and `battery_soc` via `MAPPING_4_JSON_PATH=$.meters.soc`. Round-trip
  preserves all four extraction styles (`mqtt_json_formula`,
  `mqtt_json_path`) on the same topic.
- **Battery sign convention via Envoy storage meter.**
  `MAPPING_3_FIELD_POSITIVE=bat_power_minus` /
  `_FIELD_NEGATIVE=bat_power_plus` reflects Envoy semantics (positive
  payload = battery discharging). Round-trip emits four directional
  formulas (`IF(... > 0, ..., 0)` / `IF(... < 0, -..., 0)`) so charging
  power still lands in `bat_power_plus` and discharging in
  `bat_power_minus`. Same shape user1/user7 exercise; user8 covers the
  combined grid-and-battery split on one Envoy payload.
- **Three-MPPT SENEC via per-string Home Assistant bridge.**
  `INFLUX_SENSOR_INVERTER_POWER_1/2/3=xxx-pv-messung:pv_ost/pv_sued/pv_west`
  fed by `MAPPING_13/14/15` from `forSOLECTRUS/pv_ost`, `_pv_sued`,
  `_pv_west` topics. Round-trips as `inverter_power_1/2/3` with
  `source: mqtt` and the donor's per-string topics attached — distinct
  from user6/user7 where the same shape used `source: external`.
- **espaltherma multi-field heat pump formula with German keys.** Most
  complex `mqtt_json_formula` across all fixtures.
  `MAPPING_8_JSON_FORMULA` computes heating power from five JSON
  fields — `{Aktuelle Betriebsart}`, `{Frostschutz}`,
  `{R1T-Wasser Vorlauftemp. nach dem Plattenwärmetauscher}`,
  `{R4T-Wasser Rücklauftemp. vor dem Plattenwärmetauscher}`,
  `{Durchflussmenge (l/min)}` — applying `flow * 60 * 1.163 * delta_T`
  (specific heat capacity of water) when the unit is actively heating
  and not in frost protection. Round-trip preserves every umlaut,
  parenthesis, slash, and dot in the JSON keys verbatim.
- **Heat pump status formula with `==` and German string operands.**
  `MAPPING_10_JSON_FORMULA` uses double-equals comparisons
  (`{Frostschutz} == 'ON'`) and emits German labels (`'Frostschutz'`,
  `'Abtauen'`, `'Warmwasser'`, `'Heizen'`, `'Warten'`) through three
  nested `IF`s. Round-trip preserves the operator and the literal
  values; YAML wraps the whole formula in single quotes and doubles the
  inner single quotes (`''ON''`), but the on-disk `.env` form is
  faithful to the donor.
- **Mixed JSON-extraction styles across slots.** Donor uses
  `JSON_FORMULA` (slots 0/2/3/8/10), `JSON_PATH` (slot 4), and
  `JSON_KEY` (slots 9/11/12/16..23/27) on different topics. Round-trip
  routes each through the matching `mqtt_json_*` config key.
- **Mixed JSON_FORMULA quoting in source.** Donor wraps some formulas
  in single quotes (`MAPPING_0_JSON_FORMULA='round(...)'`), leaves
  others bare (`MAPPING_2_JSON_FORMULA=round(...)`). Env parser strips
  both forms; export normalizes to consistent single-quoting.
- **JSON_KEY values with whitespace and umlauts.** `R1T-Außentemperatur`
  and `R5T-Brauchwassertemperatur im Speicher` (multi-word with space)
  ride through both directions of the round-trip without escaping
  damage.
- **Spelling typos preserved verbatim.** Donor's measurement names
  drop the `e` from German `ue` digraphs while the topics keep them:
  `MAPPING_17_TOPIC=shelly/spuelmaschine/...` →
  `MAPPING_17_MEASUREMENT=spulmaschine`;
  `MAPPING_19_TOPIC=shelly/kuehlschrank/...` →
  `MAPPING_19_MEASUREMENT=kuhlschrank`. Importer must not normalize —
  rewriting either side would orphan the donor's historical InfluxDB
  data.
- **Inconsistent Shelly TYPE.** Slot 12 (`heizluefter`) uses
  `TYPE=integer` while every other Shelly switch slot uses `TYPE=float`.
  Donor inconsistency, preserved in round-trip.
- **MAPPING_11 reverses TYPE/FIELD order.**
  `MAPPING_11_TYPE=float` appears before `MAPPING_11_FIELD=r5t_tank_temp`
  in source `.env`. Order is irrelevant to the env parser; export
  emits canonical TOPIC→FIELD→TYPE→KEY ordering.
- **Wallbox `MAPPING_6_TYPE=boolean`** for evcc loadpoints connected
  state. user7 used `string` for the same evcc topic; both forms
  round-trip.
- **Ten populated custom-power slots.** `_01..10` track real Shelly
  appliances (`waschmaschine`, `spulmaschine`, `ebikeladestation`,
  `luftentfeuchter`, `rocket`, `kuhlschrank`, `serverschrank`,
  `3ddrucker`, `heizluefter`, `schreibtisch`) — all `source: mqtt`
  with their `shelly/<name>/status/switch:0` topic and `JSON_KEY=apower`.
  No external slots, no dead refs.
- **Three-roof forecast.solar with negative azimuth.** Donor splits a
  14.68 kWp array into three roofs (5.04 / 5.04 / 4.60 kWp); roof 0
  faces `-72°` (east of south), preserved as
  `forecast_azimuth1: "-72"` (YAML double-quotes the leading minus
  while the other azimuths sit in single quotes). Damping 0.5 morning
  and evening preserved per-section, not per-roof.
- **`INFLUX_EXCLUDE_FROM_HOUSE_POWER=HEATPUMP_POWER`** applied as
  `exclude_from_house_power: true` on the `heatpump_power` sensor;
  heat pump consumption no longer double-counts in house power.
- **Watchtower `command: --scope solectrus --cleanup` transformed.**
  HELIOS recognizes the flags, drops the `command:` override, and
  emits `WATCHTOWER_SCOPE=solectrus` + `WATCHTOWER_CLEANUP=true` in
  `.env`. Same treatment as user7, but here on the canonical
  `containrrr/watchtower` image (not the `nickfedor/` fork).
- **`FRAME_ANCESTORS="http://192.168.168.101:8123"`** preserved as
  unquoted `FRAME_ANCESTORS=http://192.168.168.101:8123` (Home
  Assistant URL). Donor's double-quoted form parses identically to
  the bare form.
- **`APP_HOST=192.168.178.225` with `FORCE_SSL=false`** — typical
  local-IP deployment without Traefik, dashboard published on
  `3000:3000` directly. Same shape as user1/user3/user4/user7.
- **Volume paths under `/var/lib/docker/volumes/solectrus/_data/...`**
  preserved verbatim. Unusual location (inside Docker's volume
  directory but used as bind mounts), but HELIOS doesn't second-guess
  the donor's choice.
- **Forecast measurement via non-canonical indirection.** Donor sets
  `FORECAST_INFLUX_MEASUREMENT=Forecast` (capital F) in `.env` and
  bridges with `INFLUX_MEASUREMENT=${FORECAST_INFLUX_MEASUREMENT}` on
  the forecast-collector service. `ForecastExtractor` reads from the
  resolved service env (`fc_env['INFLUX_MEASUREMENT']`), so it
  recovers `Forecast` regardless of which raw `.env` key the donor
  used. Round-trip emits canonical
  `INFLUX_MEASUREMENT_FORECAST=Forecast`; the dashboard sensor
  `INFLUX_SENSOR_INVERTER_POWER_FORECAST=Forecast:watt` keeps
  pointing at the same measurement. user2 also benefits — its inline
  literal `INFLUX_MEASUREMENT=Pvnode` rides the same code path.
- **Empty sensor slots correctly dropped.** Donor leaves
  `INFLUX_SENSOR_SYSTEM_STATUS_OK=` and
  `INFLUX_SENSOR_GRID_EXPORT_LIMIT=` blank. Importer treats them as
  absent — they don't appear in `config.yaml` or the exported `.env`.
  Same intentional behavior documented for user1's empty
  `INFLUX_SENSOR_INVERTER_POWER_5=`: an empty value carries no
  measurement/field, so re-emitting it would only carry dead weight
  forward.

## Lost or degraded on re-export (data loss)

- **Three distinct InfluxDB tokens consolidated lossily.**
  `INFLUX_TOKEN_READ` (dashboard), `INFLUX_TOKEN_WRITE`
  (mqtt-collector, forecast-collector) and `INFLUX_ADMIN_TOKEN`
  (power-splitter, influxdb init) carry **different** values; HELIOS
  exports a single `INFLUX_TOKEN=my-influx-admin-token`. Dashboard
  previously had read-only access; after round-trip it gets the admin
  token — same privilege-escalation side effect documented for user5.
  (user6 and user7 had identical token values, so consolidation was
  lossless there.)

## Equivalent on re-export (no operational impact)

These look like changes in the diff but don't alter what the stack
actually does — HELIOS's defaults match the donor's explicit values,
or the value is simply re-spelled.

- **`INFLUX_HOST=influxdb` / `INFLUX_PORT=8086` / `INFLUX_SCHEMA=http`**
  dropped — HELIOS bakes these into compose service-network addressing
  for dashboard, mqtt-collector, forecast-collector, and power-splitter.
- **`INFLUX_USERNAME=admin`** dropped from `.env`; HELIOS hardcodes
  `DOCKER_INFLUXDB_INIT_USERNAME=admin` in the InfluxDB service. Donor
  happened to use the same value, so re-init against an empty volume
  would produce identical credentials.
- **InfluxDB `command:` override dropped.** Donor spelled out
  `influxd run --bolt-path /var/lib/influxdb2/influxd.bolt
  --engine-path /var/lib/influxdb2/engine --store disk` — these are
  the InfluxDB 2.x defaults, identical behavior under the image
  default. Same as user7.
- **Inline literal `INFLUX_TOKEN=${INFLUX_TOKEN_READ/WRITE/ADMIN_TOKEN}`**
  rewritten to plain `INFLUX_TOKEN`, pulling from the consolidated
  value above.
- **`FORECAST_INFLUX_MEASUREMENT=Forecast` indirection collapsed.**
  Service env line `INFLUX_MEASUREMENT=${FORECAST_INFLUX_MEASUREMENT}`
  rewritten to `INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_FORECAST}` on
  the forecast-collector — canonical variable name with the same
  resolved value (`Forecast`).
- **`POWER_SPLITTER_INTERVAL` referenced in compose, undefined in
  `.env`.** Donor's running stack therefore had an empty value (no
  override of the power-splitter image default). HELIOS pins the var
  to a fixed `300` (5-minute cadence) for every stack, faster than the
  power-splitter's own `3600` fallback the donor was running.
- **Forecast vars referenced but undefined dropped.** Compose lists
  `FORECAST_HORIZON`, `FORECAST_INVERTER`, `FORECAST_SOLAR_APIKEY`,
  `SOLCAST_APIKEY`, `SOLCAST_SITE`, `SOLCAST_0_SITE`, `SOLCAST_1_SITE`
  in the forecast-collector environment block, none defined in `.env`.
  Silent drop matches what the running stack saw — these were dead
  refs in the donor too.
- **Dashboard `CO2_EMISSION_FACTOR`** referenced in compose env list
  but undefined in `.env`. Silent drop, no operational change.
- **Healthcheck timings normalized.** Donor's
  `interval: 30s` / `timeout: 10s` / `start_period: 30s|60s` replaced
  with HELIOS's shorter standard intervals (`interval: 10s` /
  `timeout: 5s` plus a `start_interval: 2s`). Same probes, faster
  startup.
- **`links: - influxdb` (legacy) dropped** from forecast-collector,
  mqtt-collector, and power-splitter. Compose v2 ignores `links` for
  service-network resolution; HELIOS doesn't re-emit it.
- **Sensor reordering on export.** Donor numbers MQTT mappings in
  feature-grouped order (Envoy → wallbox → heat pump → Shelly arrays);
  export sorts sensors alphabetically and renumbers slots
  `0..29`, splitting the two signed-split mappings into four (net +2
  vs. donor's 28).
