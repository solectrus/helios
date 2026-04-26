# legacy_images

Round-trip fixture that exercises the **legacy-image upgrade policy**
defined in [`DockerImages`](../../../../app/models/docker_images.rb).
Every infrastructure service in `compose.yaml.bak` carries a tag from
the `:legacy` list — import (and the next render) must rewrite each
one to its `:current` default.

## Highlights

- **Dashboard preview tag** `ghcr.io/solectrus/solectrus:pr-4588`
  → upgraded to `:latest` on the next stack render. The dashboard
  upgrade is applied by `Export::Builder#upgrade_managed_images!`,
  not by the importer, so `config.yaml` still records `pr-4588`
  while `compose.yaml` already shows `:latest`.
- **Old InfluxDB tag** `influxdb:2.5-alpine` → `:2.8-alpine`. Force
  upgrade on import — InfluxDB 2.x storage is forward-compatible, so
  HELIOS lifts every entry on `DockerImages::INFLUXDB[:legacy]` to
  the current default regardless of what the user had pinned.
- **Old Redis tag** `redis:6-alpine` → `:8-alpine`. Same force-upgrade
  rationale: in-memory cache, no persistence concerns.
- **Deprecated Watchtower repo** `containrrr/watchtower:1.7.1` →
  `nickfedor/watchtower:latest`. The legacy entry is the bare repo
  name (no tag), so any tag from the unmaintained repo is migrated
  to the maintained fork.
- **PostgreSQL preserved** — `postgres:16-alpine` is kept verbatim
  even though `:current` is `postgres:18-alpine`.
  `DockerImages::POSTGRESQL[:legacy]` is empty by design: a major-
  version bump is not safe in place, so HELIOS leaves the user's
  pinned tag alone and lets them migrate manually.
