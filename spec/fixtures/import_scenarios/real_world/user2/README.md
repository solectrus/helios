# user2

Real-world `compose.yaml` + `.env` from a SOLECTRUS user running a self-built,
heavily customized stack with 13 custom power sensors, multi-plane pvnode
forecasts, and a Tibber price feed. Anonymized but otherwise untouched.

## Highlights

- **YAML anchors and merge keys** — the source compose leans on `x-image-*`
  anchors and `<<: *logging` / `<<: *environment_influxdb` merges to share
  config across services. The importer must allow aliases when parsing the
  raw compose, and deep-dup the parsed tree so re-emitted YAML in
  `_unmanaged.services` doesn't leak `&1 / *1` anchors back into config.yaml.
- **`DOCKER_INFLUXDB_INIT_PASSWORD` instead of `INFLUX_PASSWORD`** — the
  user wires the InfluxDB admin password through the InfluxDB-native env var
  rather than HELIOS's canonical name. Without a fallback, the importer would
  fail to find a password and `Export::Builder#ensure_defaults!` would
  generate a fresh random one on every run, breaking round-trip stability.
- **`DOCKER_INFLUXDB_INIT_ADMIN_TOKEN` set alongside `INFLUX_TOKEN`** —
  redundant with the canonical token; the fallback chain absorbs the
  InfluxDB-native form so the value is preserved if a stack ever ships only
  the DOCKER_-prefixed name.
- **Unmanaged Mosquitto service** — full config (volumes, traefik labels,
  healthcheck, tmpfs log mount) is preserved verbatim under
  `_unmanaged.services.mosquitto`. The user runs their own MQTT broker.
- **Two mqtt-collector instances** — the user runs `mqtt_collector_influxdb`
  (the regular SENEC mappings) *and* a second `mqtt_collector_ingest` that
  feeds custom battery telemetry into the ingest service. Both share
  `ghcr.io/solectrus/mqtt-collector` as their image. HELIOS picks the first
  one as the canonical `mqtt-collector` (extracts its broker config and
  MAPPING_N_* into `mqtt:` and `sensors.*`), and keeps the second under its
  original name in `_unmanaged.services.mqtt_collector_ingest` — the
  `INGEST_MAPPING_0_*` env vars are attached there as `env_values` so the
  relationship stays explicit on re-export instead of leaking into orphan
  `_unmanaged.env_vars`.
- **Energy-tracking orphan mappings** — `MAPPING_6` (`ac_bedroom:energy_in`)
  and `MAPPING_8` (`dish_washer:energy_in`) collect kWh totals via
  `JSON_FORMULA` divisions; no HELIOS sensor consumes the
  `measurement:energy_in` pair (only `:power` is bound). Preserved under
  `mqtt.mappings:` and re-emitted as trailing `(additional)` entries so the
  energy time series keeps growing in InfluxDB. Editable via the MQTT
  settings UI.
- **Hash-style `environment:` blocks** — every service in the source compose
  uses the `KEY: ${VAR}` mapping form (often combined with `<<:` merges),
  not the `- KEY=value` array form. The importer normalizes hash environments
  to array form before processing so referenced-var detection works uniformly.
- **Unmanaged Tibber collector** — `ghcr.io/solectrus/tibber-collector:0.4.1`
  isn't recognized by HELIOS; preserved verbatim with its `TIBBER_*` env
  vars attached to the service's `env_values` so the price feed survives
  re-export.
- **Multi-plane pvnode forecast (4 roofs)** — `PN_FORECAST_0..3_*` env vars
  map cleanly to `forecast_declination/azimuth/kwp{1..4}`, and per-plane
  `PVNODE_0..3_EXTRA_PARAMS` map to `forecast_pvnode_extra_params{1..4}`.
- **Legacy forecast.solar config left in `.env`** — leftover
  `FS_FORECAST_CONFIGURATIONS=4` and `FORECAST_2_INVERTER=0.86` from a
  pre-pvnode setup. Preserved as `_unmanaged.env_vars`; HELIOS's active
  forecast is pvnode.
- **Custom-named SENEC measurement (`SENEC`)** — uppercase variant flows
  through to sensor measurements (`inverter_power_1` → `SENEC:inverter_power`).
- **Calculated house power** — `INFLUX_SENSOR_HOUSE_POWER` points at
  `Calculated:house_power` (the power_splitter output bucket), exercising
  the importer's split between source measurement and field.
- **13 custom power sensors** — `CUSTOM_POWER_01..13` are all populated.
  `01` (heatpump), `08` (well_pump), and `13` (anker-akku) are flagged
  `exclude_from_house_power: true` via `INFLUX_EXCLUDE_FROM_HOUSE_POWER`.
- **`heatpump_power` excluded from house power** — explicitly listed in
  `INFLUX_EXCLUDE_FROM_HOUSE_POWER` alongside the custom sensors.
- **Empty inverter slots** — `INFLUX_SENSOR_INVERTER_POWER` and slots `_4`
  and `_5` are blank and must be dropped, while `_1..3` are kept.
- **Develop-tagged ingest image** — `ghcr.io/solectrus/ingest:develop`
  preserved verbatim instead of falling back to a release tag.
- **Commented-out alternatives in compose.yaml** — multiple x-image
  variants are commented out (e.g. `image_solectrus:power-balance-chart`
  active, `:0.20.2` and `:develop` commented). The importer follows the
  active line; comments are not preserved on re-export (acceptable per
  CLAUDE.md).
- **Custom healthchecks replaced by HELIOS defaults** — e.g. influxdb's
  curl-based ping is replaced by `influx ping`. Deliberate: HELIOS uses
  the native CLI bundled with the image instead of requiring `curl`,
  which is more robust and avoids assumptions about HTTP-API exposure.
- **Redundant `command:` overrides dropped** — influxdb's
  `influxd run --bolt-path /var/lib/influxdb2/influxd.bolt
  --engine-path /var/lib/influxdb2/engine --store disk` only respells
  the official image's built-in defaults (`INFLUXD_BOLT_PATH` /
  `INFLUXD_ENGINE_PATH` env vars; `disk` is the production default for
  `--store`). Same pattern in user1's `watchtower` (`--scope solectrus
  --cleanup` duplicates the `WATCHTOWER_SCOPE` / `WATCHTOWER_CLEANUP`
  env vars HELIOS already renders). Dropping these on re-export is
  lossless and intentional.

## Compose keys dropped on re-export

The fixture also documents what HELIOS currently *cannot* round-trip on
managed services. Diffing `compose.yaml.bak` against the regenerated
`compose.yaml` shows several keys that are silently lost because
`config.yaml` doesn't model them:

- **Traefik labels and the `traefik` external network** — multiple
  managed services (dashboard, influxdb, ingest, …) had `traefik.*`
  labels and were attached to a second `traefik` network. After regen:
  labels gone, services exposed via direct `ports:` on the host instead
  of `expose:`. Breaks reverse-proxy routing.
- **Custom bind-mount paths** — InfluxDB / Postgres / Redis pointed at
  `${BASE_DIR}/...` outside the stack directory. HELIOS rewrites these
  to relative `./service/...` paths (per ADR-0003). After regen,
  containers mount empty directories — the original data still exists
  on disk but is no longer visible to the running container.
- **Backup / dump volumes** — `${HOST_DUMP}:${CONTAINER_DUMP}` on
  postgres / influxdb / redis is dropped entirely.
- **`deploy.resources.limits` on managed services** — `cpus` / `memory`
  caps on the forecast and senec collectors are dropped (kept correctly
  for unmanaged services like `tibber_collector`).
- **Externally published ports** — e.g. `ports: "5432:5432"` on
  postgres is dropped if HELIOS doesn't model an external port for that
  service.

Surfacing these in the auto-import review screen (or a per-service
`_overrides` block in `config.yaml`) is out of scope until users run
into the warning in the wild.
