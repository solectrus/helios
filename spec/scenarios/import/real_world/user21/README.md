# user21

Real-world `docker-compose.yml` + `.env` from a long-running SOLECTRUS user on
a Synology NAS (`/volume1/docker/...` bind-mounts), running an `INSTALLATION_DATE=2020-06-01`
stack that is the oldest specimen in the test corpus — written when SOLECTRUS
followed the original Docker hosting guide and predates HELIOS itself by years.
Anonymized but otherwise untouched.

## Highlights

- **`docker-compose.yml.bak` filename, not `compose.yaml.bak`** — the donor
  uses Docker Compose v1's historical filename. `Compose::FILENAMES` accepts
  every variant, so the importer finds the file and the round-trip spec
  resolves the same backup path via the lazy `FILENAMES.map` lookup.
- **Compose v1 idioms preserved through import** — `version: "3.7"` top-level
  key, deprecated `links:` directives, and `network_mode: host` on every
  service. All are dropped on re-export: the schema header is obsolete in
  Compose v2, `links` is unused with the default bridge network, and the
  exported stack runs on the canonical `solectrus_default` network with
  `INFLUX_HOST=influxdb` / `DB_HOST=postgresql` / `REDIS_URL=redis://redis:6379/1`
  resolving by container name instead of host loopback.
- **Legacy service names `app:` and `db:`** — Dashboard is `app:` and
  PostgreSQL is `db:`, matching the original SOLECTRUS hosting guide rather
  than the canonical `dashboard:` / `postgresql:` names. Aliased via
  `StackReader::SERVICE_IMAGE_PREFIXES` and re-exported under the new names
  (same convention as [user20](../user20/README.md)).
- **Legacy `ghcr.io/solectrus/solectrus:latest` image** — the historical
  Dashboard repository before the `dashboard` rename. Preserved verbatim
  through `SERVICE_IMAGE_PREFIXES['dashboard'] = %w[ghcr.io/solectrus/solectrus]`
  rather than auto-rewritten to `ghcr.io/solectrus/dashboard`, so the user
  keeps running the image they already pull.
- **Pinned vintage images** — `influxdb:2.1.1-alpine` (pinned to a four-year-old
  patch release), `postgres:14-alpine`, and `redis:alpine` (no tag at all).
  Round-tripped unchanged; HELIOS will not silently upgrade a user off
  their on-disk InfluxDB 2.1 / Postgres 14 data formats.
- **Synology bind-mount paths** — `/volume1/docker/solectrus/dashboard/{influxdb,postgresql,redis}`
  survive verbatim under each section's `volume_path:` and re-emit as
  `${INFLUX_VOLUME_PATH}` / `${DB_VOLUME_PATH}` / `${REDIS_VOLUME_PATH}` in
  the new compose. The `postgres:14` mount target stays `/var/lib/postgresql/data`,
  same major-version-aware export logic that fixed issue #124 in
  [user20](../user20/README.md).
- **Pre-sensor-architecture stack — collector-default sensor synthesis** — the
  donor predates per-sensor InfluxDB mappings: there is not a single
  `INFLUX_SENSOR_*`, `INFLUX_MEASUREMENT_*`, or `MAPPING_*` variable in
  `.env.bak`. The senec-collector and forecast-collector still write into the
  collector's compiled-in measurement (`SENEC` / `forecast`), so HELIOS'
  `LegacySensorAdapter` falls back to those names — without an explicit
  `INFLUX_MEASUREMENT_PV/FORECAST` — and synthesizes the full SOLECTRUS
  default sensor set (12 senec sensors + `inverter_power_forecast`). Result:
  `config.yaml` retains the user's `senec:` / `forecast:` sections AND a
  populated `sensors:` map, and the re-exported `compose.yaml` keeps the
  senec-collector and forecast-collector services intact. The collector-only
  fallback is gated by "no `INFLUX_SENSOR_*` of any kind in the env" so it
  doesn't second-guess users who have already started per-sensor configuration.
- **Single InfluxDB token reused across all three roles** — the donor's
  `.env` candidly notes that "*to keep things simple, we use ONE token
  (INFLUX_ADMIN_TOKEN) for both writing and reading*", and sets
  `INFLUX_TOKEN_WRITE == INFLUX_TOKEN_READ == INFLUX_ADMIN_TOKEN`. HELIOS
  preserves all three (plus the synthesized `INFLUX_TOKEN_READWRITE`) at the
  same value instead of rotating them to distinct secrets.
- **Per-service `INFLUX_TOKEN` alias is reproduced** — donor pins
  `INFLUX_TOKEN=${INFLUX_TOKEN_READ}` on the Dashboard so a read-only token
  is used at query time. The re-exported Dashboard env block re-emits the
  same `INFLUX_TOKEN=${INFLUX_TOKEN_READ}` inline reference rather than
  collapsing to the generic `INFLUX_TOKEN` var.
- **Inline comment inside an env value** — `SENEC_HOST=192.168.178.34 # change this!!!`.
  POSIX shell parsing treats everything after the `#` as part of the value,
  but HELIOS' env parser splits on the comment and stores only
  `192.168.178.34`. Since no senec-collector is re-emitted (see sensor
  point above), this is moot for the round-trip — but the trailing
  exhortation is silently dropped, which matches behavior on other scenarios
  that carry decorative inline comments.
- **Commented-out `renault-collector:` block** — six-line YAML comment in
  `docker-compose.yml.bak`. The Compose parser never sees it, so nothing to
  import and nothing to round-trip; included here only as evidence that the
  importer doesn't choke on heavily-annotated donor files.
- **`#ssword` truncated comment** — line 22 of `.env.bak` is the donor's
  literal typo (`#ssword for the PostgreSQL database`, the leading `#pa` was
  lost). The env parser ignores comments, so the typo round-trips into
  oblivion when HELIOS rewrites `.env` with its own curated headers.
- **No `ADMIN_PASSWORD` in the donor — HELIOS derives one on export** — the
  variable did not exist when this 2020 install was first deployed
  (`ADMIN_PASSWORD` was introduced by SOLECTRUS commit
  [`745b7c75` "Add Admin login"](https://github.com/solectrus/solectrus/commit/745b7c75)
  on 2022-08-06, over two years later) and the donor never backfilled it.
  Without one, SOLECTRUS boots but its admin actions (settings, prices, …)
  are inaccessible, so HELIOS treats `admin_password` as auto-generated:
  `ConfigSchema::SYSTEM_DEFAULTS` derives it deterministically as
  `sha256(secret_key_base)[0..31]`. For this fixture's
  `SECRET_KEY_BASE=my-secret-key-base` that resolves to
  `283aebd3f655573d2e551dd0aa9c13f4` — the same value HELIOS produces on
  every export and the same value `bootstrap/install.sh`'s
  `ensure_helios_secrets` would compute during a real adoption (both
  pathways share the algorithm). The value lands in **both** `config.yaml`
  (`system.admin_password`) and the generated `.env`, so any later
  import/UI-edit cycle keeps it stable instead of regenerating fresh
  values from scratch.
- **Watchtower synthesized from defaults** — donor has no Watchtower service,
  yet the export emits one with `image: nickfedor/watchtower:latest` and
  `WATCHTOWER_POLL_INTERVAL=86400`. This is HELIOS' baseline policy
  (`WATCHTOWER_DEFAULTS`), not import behavior — every managed stack ships
  with a Watchtower so update notifications work out of the box.
