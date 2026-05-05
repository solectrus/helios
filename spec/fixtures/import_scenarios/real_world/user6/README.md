# user6

Real-world `compose.yml` + `.env` from a SOLECTRUS user running behind
Traefik with Let's Encrypt, a SENEC V3 inverter (two MPPTs), Viessmann
heat pump telemetry, a Shelly Pro 3EM heat-pump submeter, and ten
Tasmota/Shelly plug measurements feeding the dashboard via a generous
MQTT mapping table. Anonymized but otherwise untouched.

## Imported correctly (round-trip preserves the value)

- **Alternate compose filename** — donor uses `compose.yml.bak` (not
  `compose.yaml.bak`); the importer's `Compose::FILENAMES` lookup picks
  it up regardless. First fixture to exercise the `.yml` variant.
- **Watchtower fork image preserved** — `nickfedor/watchtower` (the
  community fork that replaced unmaintained `containrrr/watchtower`)
  round-trips as `nickfedor/watchtower:latest`. HELIOS recognizes it as
  the managed Watchtower service rather than treating it as unmanaged.
- **`WATCHTOWER_CLEANUP=true` and `WATCHTOWER_SCOPE=solectrus`** — both
  carried into the managed Watchtower env block.
- **`WATCHTOWER_SCHEDULE='0 5 2 * * *'`** — donor uses the 6-field
  cron-with-seconds format. HELIOS exposes only `WATCHTOWER_POLL_INTERVAL`
  in its UI, so the schedule survives verbatim under
  `_unmanaged.env_vars` and re-emits with the original quoting.
- **SENEC V3 with two MPPTs** — `INFLUX_SENSOR_INVERTER_POWER_1=mpp1_power`
  and `_2=mpp3_power` (note the gap: MPPT 2 is unused) become
  `inverter_power_1` / `inverter_power_2` with `source: external`.
  Single-measurement (`SENEC`) keeps the importer's balcony heuristic
  silent, same as user5.
- **Two-roof pvnode forecast** — `FORECAST_PROVIDER=pvnode`,
  `FORECAST_CONFIGURATIONS=2`, per-roof `FORECAST_0/1_AZIMUTH` and
  `_KWP`, plus `PVNODE_APIKEY`, `PVNODE_PAID=true`, and the long
  `PVNODE_EXTRA_PARAMS=diffuse_radiation_model=perez&mounting_type=isol&shading_config=...&panel_age_years=2`
  query string round-trip through `forecast.forecast_pvnode_*`.
- **Inline `# east` / `# west` comments after `FORECAST_0/1_AZIMUTH`
  values** — the env parser strips trailing comments, so `267.5 # east`
  becomes the float `267.5` cleanly.
- **Commented-out alternatives ignored** — the donor keeps a full
  `# FORECAST_PROVIDER=solcast` block, `# INFLUX_SENSOR_INVERTER_POWER=`,
  `# APP_HOST=167.235.236.85`, and `# INFLUX_MEASUREMENT_PV=SENEC`
  alongside their active replacements; only the live values are imported.
- **MQTT broker config** — `MQTT_HOST=mosquitto`, `MQTT_PORT=1883`,
  `MQTT_SSL=false`, plus credentials carried into the managed
  `mqtt-collector` service.
- **15 MQTT mappings (`MAPPING_0..14`) with mixed shapes** — wired into
  the right destinations:
  - `MAPPING_0` (`ds3/soc`) → `car_battery_soc` sensor.
  - `MAPPING_1..7` (Shelly/Tasmota plugs with `JSON_KEY=apower` or
    `JSON_PATH=$.ENERGY.Power`) → `custom_power_01..07`.
  - `MAPPING_9` (`shellypro3em` with `JSON_KEY=total_act_power`) →
    `heatpump_power`.
  - `MAPPING_10..12` (Viessmann generated heat / outside / tank temp)
    → `heatpump_heating_power`, `outdoor_temp`, `heatpump_tank_temp`.
  - `MAPPING_8` (`ds3/mileage`), `MAPPING_13` (`compressorStarts`),
    `MAPPING_14` (`compressorHours`) → kept under `mqtt.mappings` because
    no managed sensor matches.
  Re-export renumbers them 0..14 with sensor-aligned ordering, so the
  raw indices shift but every payload survives.
- **`INFLUX_EXCLUDE_FROM_HOUSE_POWER=HEATPUMP_POWER`** — applied as
  `exclude_from_house_power: true` on the `heatpump_power` sensor.
- **`POWER_SPLITTER_INTERVAL=300`** — inlined into the power-splitter
  service's `environment:` block (same pattern as user3..user5).
- **`INFLUX_MEASUREMENT_FORECAST=Forecast`** — preserved as
  `forecast.measurement: Forecast` and re-emitted on export.
- **External Traefik adopted as managed reverse proxy with
  pass-through overrides.** Donor's `traefik:` service uses custom
  entrypoints (`influxdb:8086` / `pgadmin:8888` / `dozzle:9090` /
  `mqtt:8883`), a custom resolver name (`myresolver`), ACME email
  `postmaster@example.com`, `./letsencrypt` volume, `restart: always`,
  and a router named `app-solectrus` on the dashboard.
  `ReverseProxyExtractor` accepts any `routers.<name>.rule` (not only
  `routers.dashboard.rule`), extracts the host `solectrus.example.com`,
  and captures `command`, `ports`, `volumes`, `restart`, `labels`,
  `environment` verbatim into `reverse_proxy.*` whenever a custom
  `command` is present. The exported `compose.yaml` reproduces the
  donor's Traefik service exactly, `Traefik.enabled?` returns `true`,
  and `FORCE_SSL=true` follows automatically.
- **Global `FORECAST_DECLINATION=30` fanned out per roof.** Donor
  declared a single unprefixed declination shared by both roofs;
  `ForecastExtractor#multi_roof_data` now falls back to the global
  value when per-roof `FORECAST_#{i}_DECLINATION` is missing, so
  `forecast_declination1`/`_2` both round-trip as `30`.

## Lost or degraded on re-export (real data loss)

- **Per-service Traefik routing labels on non-dashboard managed
  services stripped.** Donor routed `influxdb` (entrypoint `influxdb`),
  `pgadmin` (entrypoint `pgadmin`), and `mosquitto` (TCP/SNI rule)
  through Traefik via per-service labels, plus a `test-ratelimit`
  middleware on the dashboard. HELIOS regenerates these services from
  its managed templates, so the extra label sets don't survive. The
  dashboard's own Host rule round-trips fine — only the auxiliary
  services lose their routing.
- **`mqtt-collector` `privileged: true` dropped.** Donor ran the
  collector with elevated privileges (no operational reason apparent,
  but a deliberate setting nonetheless); HELIOS doesn't model
  `privileged:` and silently drops it.

## Equivalent on re-export (no operational impact)

These look like changes in the diff but don't alter what the stack
actually does — HELIOS's defaults match the donor's explicit values,
or the value is simply re-spelled.

- **`INFLUX_PORT=8086` / `INFLUX_SCHEMA=http` / `INFLUX_HOST=influxdb`
  dropped** — HELIOS bakes these into compose service-network
  addressing for dashboard, mqtt-collector, forecast-collector, and
  power-splitter, so the runtime endpoint is unchanged.
- **`INFLUX_USERNAME=admin` dropped.** HELIOS initializes with the
  default `solectrus` username; harmless against an already-initialized
  volume (the donor's running InfluxDB ignores `DOCKER_INFLUXDB_INIT_*`).
- **Three identical InfluxDB tokens consolidated.** `INFLUX_ADMIN_TOKEN`,
  `INFLUX_TOKEN_WRITE`, and `INFLUX_TOKEN_READ` all hold the same value
  in the donor, so HELIOS's single `INFLUX_TOKEN` is lossless here
  (contrast user5 where divergent token values caused privilege
  escalation).
- **InfluxDB `command:` override dropped.** Donor spelled out
  `influxd run --bolt-path /var/lib/influxdb2/influxd.bolt --engine-path
  /var/lib/influxdb2/engine --store disk` — these are the InfluxDB 2.x
  defaults, so the image default produces identical behavior.
- **Inline literal `INFLUX_TOKEN=${INFLUX_TOKEN_READ}` (dashboard) /
  `=${INFLUX_TOKEN_WRITE}` (forecast-collector, mqtt-collector) /
  `=${INFLUX_ADMIN_TOKEN}` (power-splitter)** rewritten to plain
  `INFLUX_TOKEN`, pulling from the consolidated value above.
- **Custom-power slots `_08..10` referenced but undefined** — already
  dead refs in the donor (`environment:` lists them, `.env` doesn't
  define them); silent drop matches what the running stack saw.
- **3-space-indented `volumes:` in `mosquitto`** normalized to
  2-space. Pure formatting.

## Unmanaged services preserved

- **`dozzle`** — log viewer with `DOZZLE_AUTH_PROVIDER: simple` and
  `./dozzle/data` volume; preserved verbatim under
  `_unmanaged.services.dozzle`, including its Traefik labels and
  Watchtower scope.
- **`pgadmin`** — `dpage/pgadmin4` with literal email/password env
  vars and `./pgAdmin` (capitalized!) volume mount; preserved with
  Traefik labels and `service: pgadminservice` TCP loadbalancer route.
- **`mosquitto`** — `eclipse-mosquitto` MQTT broker with
  `./mosquitto:/mosquitto` and `./mosquitto/data:/mosquitto/data`
  volumes plus Traefik TCP `HostSNI` route; preserved verbatim.
