# deprecated_hosting_guide

Legacy SOLECTRUS hosting-guide layout from several HELIOS iterations ago.
Verifies that the importer still recognises outdated naming and structure.

## Source

`docker-compose.yml.bak` and `.env.bak` are byte-identical copies of the
upstream [Raspberry Pi guide](https://github.com/solectrus/hosting/tree/main/guide/raspberry-pi).
The backup keeps the historical `docker-compose.yml` filename so this
scenario also verifies that HELIOS accepts legacy compose filenames at
import time (alongside `compose.yaml` and `docker-compose.yaml`).

## Highlights

- **Legacy filename** `docker-compose.yml` — HELIOS locates the compose
  file via `Compose::FILENAMES`, so the import works regardless of which
  of the three historical names the user has on disk.
- **Obsolete Compose syntax** — top-level `version: '3.7'` and explicit
  `links:` between services. Both are silently dropped on import; modern
  Compose ignores `version` and uses default networking.
- **Old service names** `app:` (instead of `dashboard:`) and `db:` (instead
  of `postgresql:`) must be remapped to the canonical HELIOS keys.
- **Old image references** `postgres:16-alpine`, `redis:7-alpine`,
  `influxdb:2.7-alpine`, `containrrr/watchtower` (now `nickfedor/watchtower`).
  HELIOS recognises them via image-name heuristics, not the tag; the
  outdated tags are preserved in `config.yaml` as explicit overrides.
- **Split InfluxDB tokens** (`INFLUX_TOKEN_READ` / `INFLUX_TOKEN_WRITE`)
  collapse into a single `token`; `INFLUX_ADMIN_TOKEN` is promoted to the
  canonical `INFLUX_TOKEN`.
- **Renamed measurement variable** `INFLUX_MEASUREMENT_PV=SENEC` becomes
  `INFLUX_MEASUREMENT_SENEC=SENEC` on export.
- **Legacy forecast variables** without an index (`FORECAST_DECLINATION`,
  `FORECAST_AZIMUTH`, `FORECAST_KWP`) are promoted to
  `forecast_declination1` / `forecast_azimuth1` / `forecast_kwp1`
  in `config.yaml`.
- **No `INFLUX_SENSOR_*` mappings** in `.env` → sensors are inferred
  implicitly from the SENEC collector (`source: senec`).
- **Default-equivalent variables dropped** — `FORCE_SSL=false`,
  `WEB_CONCURRENCY=0`, `INFLUX_HOST=influxdb`, `INFLUX_SCHEMA=http`,
  `INFLUX_PORT=8086`, `INFLUX_USERNAME=admin`, `INFLUX_POLL_INTERVAL=5`,
  and the `*_VOLUME_PATH` triplet all match HELIOS defaults and disappear
  from the exported `.env`.
- **`TZ=Europe/Berlin` added** — the legacy guide had no timezone variable;
  HELIOS injects one because every current service consumes it.
- **Comments in `.env.bak` are not preserved** — the file is regenerated
  with HELIOS section headers. Comment preservation only kicks in on
  round-trips of an already-HELIOS-managed `.env`.
