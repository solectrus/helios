# user20

Real-world `compose.yaml` + `.env` from a long-running SOLECTRUS user on
Proxmox, anonymized but otherwise untouched. Donated via the HELIOS support
bundle attached to [issue #124](https://github.com/solectrus/helios/issues/124),
where importing this exact stack silently created an empty PostgreSQL
database. This snapshot is the regression guard for that bug.

## Highlights

- **Version-correct Postgres mount target (issue #124)** — the source `db:`
  service runs `postgres:16-alpine` and bind-mounts
  `${DB_VOLUME_PATH}:/var/lib/postgresql/data`, the native image `VOLUME`
  for `postgres:17` and older. HELIOS used to hardcode the `postgres:18`
  target `/var/lib/postgresql` for every image; against a `postgres:16`
  stack that made the container look in a non-existent `data/` subdir and
  silently initialize a fresh, empty database. The export target now tracks
  the image major version (see ADR-0003), so HELIOS re-emits
  `${DB_VOLUME_PATH}:/var/lib/postgresql/data` unchanged — no `PGDATA`
  override, the bind mount round-trips byte-identical to the donor's.
- **Legacy service names `app` and `db`** — the source compose calls the
  SOLECTRUS Dashboard `app:` and PostgreSQL `db:` (their names in the original
  hosting guide), not the canonical `dashboard:` / `postgresql:`. The importer
  aliases both via `SERVICE_IMAGE_PREFIXES` and re-exports under the new names.
- **Legacy `influxdb:2.7-alpine` and `redis:7-alpine` images** — pinned older
  images are preserved verbatim instead of being auto-upgraded to the HELIOS
  defaults, so the stack keeps reading its existing on-disk data.
- **Custom Watchtower image `nickfedor/watchtower`** — preserved as
  `nickfedor/watchtower:latest` (explicit tag) and its inline
  `WATCHTOWER_POLL_INTERVAL=28800` is picked up from the service env.
- **Inconsistent measurement names** — `INFLUX_SENSOR_INVERTER_POWER` uses
  `my-pv-measurement` (hyphen), but `INVERTER_POWER_1..4` use
  `my_pv_measurement` (underscore). Both forms round-trip 1:1; rewriting them
  would lose access to historical InfluxDB data.
- **Empty `INFLUX_SENSOR_INVERTER_POWER_5=`** — dropped, not exported as an
  empty mapping.
- **Orphan MQTT mappings** — `MAPPING_5/6/7` push `mpp1/2/3_power` into
  `my-pv-measurement` with no matching HELIOS sensor. Preserved under
  `mqtt.mappings:` so the mqtt-collector keeps ingesting the topics.
- **`MQTT_TOPIC_BAT_VOLTAGE=evcc/site/homePower`** — legacy MQTT-collector
  variable outside `DEPRECATED_TOPIC_VARS`; dropped silently rather than
  carried forward as unmanaged.
- **Duplicate `FORECAST_INFLUX_MEASUREMENT=forecast`** — non-canonical alias
  of `INFLUX_MEASUREMENT_FORECAST`; its value round-trips via the canonical
  var, so the alias is dropped silently rather than carried forward as
  `_unmanaged.env_vars`.
- **Shelly collector dropped** — the source compose declares a
  shelly-collector service, but `SHELLY_HOST` and `SHELLY_INTERVAL` are
  commented out in `.env`, so the service was inactive and is correctly
  omitted on re-export.
