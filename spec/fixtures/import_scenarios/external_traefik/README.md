# external_traefik

Real-world stack derived from a SOLECTRUS deployment that runs the
self-contained "dashboard half" as a plain `docker compose` project, behind an
**external Traefik** on another host/stack. The device collectors run
elsewhere and push into this stack's InfluxDB, so they are intentionally
**not** part of this import. Anonymized but otherwise untouched.

This scenario is the corpus's coverage for the **external-Traefik + dashboard_only**
import path.

Shape of the donor stack:

- `dashboard`, `influxdb`, `db` (postgres), `redis`, `power-splitter`, a single
  `forecast-collector` (pvnode), `helios`, plus S3 backup sidecars for
  PostgreSQL and InfluxDB.
- **No Swarm `deploy:` and no Traefik labels** — an external Traefik routes to
  published **host ports**, bound to a private IP via `HELIOS_BIND_IP`
  (`10.0.0.5:3000:3000`, `…:8086:8086`, `…:3999:3000`).

## Imported correctly (round-trip preserves the value)

- **Operating mode → `dashboard_only`** — derived from "dashboard + InfluxDB
  present, InfluxDB exposed, no local device collectors (senec/mqtt/shelly)".
  forecast-collector and power-splitter don't disqualify it.
- **`HELIOS_BIND_IP` → `reverse_proxy.bind_ip`** — the bind IP is read from the
  `host_ip` of any published port and re-exported, so the ports round-trip as
  `10.0.0.5:…` (external-Traefik mode). Wildcard binds (`0.0.0.0`) are treated
  as "no bind" since that is already HELIOS's default.
- **Legacy service names `app:` / `db:`** → re-exported as `dashboard:` /
  `postgresql:` via image-prefix aliasing.
- **InfluxDB host-port publication** — the donor publishes `8086`, so
  `influxdb.publish_port: true` is captured and re-exported.
- **`FORCE_SSL=true` → `dashboard.force_ssl`** — the external Traefik ends the
  TLS connection, so the flag is captured and re-exported. Without it the login
  fails behind that proxy.
- **Single forecast-collector (pvnode)** — provider, API key, the literal
  `FORECAST_AZIMUTH=209` (→ `forecast_pvnode_azimuth1`), declination, kWp.
- **No false balcony detection** — `inverter_power_1/2/3` all share the `SENEC`
  measurement (one multi-string inverter), so `is_balcony` is not set.
- **power-splitter** — kept (mandatory `grid_import_power` + `house_power` plus a
  `wallbox_power` consumer are mapped).
- Databases' images/volumes/passwords and the InfluxDB tokens round-trip.

## Dropped or changed on import (current behaviour, documented)

- **S3 backup sidecars are dropped.** `postgres-s3-backup` /
  `influxdb2-s3-backup` are not HELIOS's backup mechanism; the `backup:` section
  stays empty and the containers are neither regenerated nor preserved. Use
  HELIOS's own backup feature instead.
- A few unmatched `.env` keys (e.g. `ASSET_HOST`,
  `INFLUXDB_BACKUP_VOLUME_PATH`) land under `_unmanaged.env_vars`.

## Takeaway

The extracted stack imports and round-trips stably: the `dashboard_only` mode
and the external-Traefik `bind_ip` are now both derived from the donor. What
still does not survive is the S3 backup sidecars — configure HELIOS's own backup
feature for those.
