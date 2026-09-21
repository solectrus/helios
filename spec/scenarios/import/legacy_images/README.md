# legacy_images

Round-trip fixture that exercises the **image-preservation policy**: HELIOS
imports every image tag exactly as it appears in `compose.yaml.bak`, even
when the tag is on the `:legacy` list defined in
[`DockerImages`](../../../../app/models/docker_images.rb).

The legacy entries do not trigger an automatic rewrite — they only power
the "Update available" hint in the service row UI, which the user opts
into manually.

## Highlights

- **Dashboard preview tag** `ghcr.io/solectrus/solectrus:pr-4588` →
  preserved. The tag is on `DockerImages::DASHBOARD[:legacy]`, so the
  service row shows an "Update available" badge that recommends
  `:latest` once the user clicks it.
- **Old InfluxDB tag** `influxdb:2.5-alpine` → preserved. Listed under
  `DockerImages::INFLUXDB[:legacy]`; the user is offered an upgrade to
  `:2.8-alpine` via the badge.
- **Old Redis tag** `redis:6-alpine` → preserved. Listed under
  `DockerImages::REDIS[:legacy]`; the user is offered an upgrade to
  `:8-alpine`.
- **Deprecated Watchtower repo** `containrrr/watchtower:1.7.1` →
  preserved. The legacy entry is the bare repo name (no tag), so any
  tag from the unmaintained repo is flagged with the badge and can be
  swapped for `nickfedor/watchtower:latest`.
- **PostgreSQL preserved** — `postgres:16-alpine` is kept verbatim.
  `DockerImages::POSTGRESQL[:legacy]` is empty by design: a major-
  version bump is not safe in place, so HELIOS leaves the user's pinned
  tag alone and never even surfaces an upgrade hint.
