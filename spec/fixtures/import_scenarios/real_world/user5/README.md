# user5

Real-world `compose.yaml` + `.env` from a SOLECTRUS user running on **Docker
Swarm** behind Traefik, with three parallel forecast-collector instances
(pvnode + solcast + forecast.solar), a heat pump, S3 backups for both
PostgreSQL and InfluxDB, and ingest active for balcony-power detection.
Anonymized but otherwise untouched.

## Imported correctly (round-trip preserves the value)

- **Legacy service names `app:` and `db:`** — renamed to `dashboard:` and
  `postgresql:` on re-export via `SERVICE_IMAGE_PREFIXES` (same as user4).
- **No false-positive balcony detection** — `inverter_power_1/_2/_3` all
  share the `SENEC` measurement (a SENEC V3's three MPPTs); the importer's
  measurement-divergence heuristic recognizes this as one multi-string
  inverter and skips the `is_balcony: true` flag. Real balcony setups
  (user2, user3, synthetic `with_ingest`) keep their flag because their
  highest-numbered slot uses a different measurement (`anker-akku:`,
  `TERRASSE:`, `Garage:`).
- **Three forecast-collector services — first-listed wins canonical
  alias.** `forecast-collector-pvnode` is declared first in the donor's
  `compose.yaml`, so HELIOS adopts it as the managed
  `forecast-collector` (`forecast: pvnode`, `measurement: Forecast`,
  pvnode API key/paid/extra-params attached).
  `forecast-collector-solcast` and
  `forecast-collector-forecast-solar` survive verbatim under
  `_unmanaged.services` with their `deploy:`, `hostname:`, `links:`,
  full environment lists, and per-instance `INFLUX_MEASUREMENT`
  values (`Forecast-Solcast`, `Forecast-Solar`) intact. Order is
  taken from `raw_compose` (original YAML), not from
  `docker compose config` (which alphabetizes and would have made
  `forecast-collector-forecast-solar` win).
- **Three distinct InfluxDB tokens preserved.** `INFLUX_TOKEN_READ`
  (dashboard), `INFLUX_TOKEN_WRITE` (forecast-collectors, ingest), and
  `INFLUX_TOKEN_READWRITE` (power-splitter) carry different values in the
  donor; HELIOS imports each into its own role (`token_read`, `token_write`,
  `token_readwrite`) and the export wires every managed service back to the
  right variable. Dashboard keeps read-only access — no privilege
  escalation. `INFLUX_ADMIN_TOKEN` falls back to the readwrite token because
  the donor has no explicit admin token.
- **Inline literal `INFLUXDB_TOKEN: "my-influxdb-admin-token"` on
  `fluxbackup`** — the user hardcoded the admin token in compose; HELIOS
  recognizes `fluxbackup` as the InfluxDB-S3 backup service and rewrites
  the literal to `INFLUXDB_TOKEN=${INFLUX_ADMIN_TOKEN}` on re-export.
- **Backup service images** — `backup.postgresql.image:
  ghcr.io/solectrus/postgres-s3-backup:18` and `backup.influxdb.image:
  ghcr.io/solectrus/influxdb2-s3-backup:latest` survive verbatim.
- **Heat pump with `INFLUX_SENSOR_HEATPUMP_POWER=Consumer:power`** —
  unusual measurement choice (`Consumer` instead of the default `HEATPUMP`)
  preserved as `source: external` with `measurement: Consumer, field: power`.
  Heating power, status, tank temp, tank-temp setpoint, and outdoor temp
  all map to `ALTHERMA:*` and round-trip cleanly.
- **`INFLUX_EXCLUDE_FROM_HOUSE_POWER=HEATPUMP_POWER`** — applied as
  `exclude_from_house_power: true` on the `heatpump_power` sensor.
- **Populated custom-power slots** — `_01`=Washer, `_02`=Fridge,
  `_06`=Dishwasher, `_08`=TV, `_09`=IT round-trip with their measurements
  and field names intact.
- **`POWER_SPLITTER_INTERVAL=300`** — HELIOS pins this to a fixed
  `300` (5-minute cadence), not configurable and not stored in
  `config.yaml`. Donor value ignored; matches here (same as user3 / user4).
- **`HONEYBADGER_API_KEY`, `RORVSWILD_API_KEY`, `PLAUSIBLE_URL`,
  `ASSET_HOST`, `DOCKER_IMAGE`** — preserved verbatim in
  `_unmanaged.env_vars`. Not re-wired into any managed service, but the
  user can reattach them manually.
- **`INSTALLATION_DATE=2022-10-01`** — round-trips as the quoted YAML
  string `'2022-10-01'` (leading digit triggers the quote).

## Lost or degraded on re-export (data loss)

- **Ingest service dropped — no balcony sensor.** Donor runs ingest for
  staging/testing without any balcony power plant. HELIOS now derives ingest
  activation strictly from the sensor configuration: at least one sensor
  flagged `is_balcony: true` is required, otherwise the service has nothing
  to recalculate. Multi-MPPT slots sharing the `SENEC` measurement aren't
  balcony sensors. Result: `ingest:` section absent from `config.yaml`,
  `ingest` service and its `RETENTION_HOURS` / `INGEST_VOLUME_PATH` env vars
  dropped on re-export.
- **Docker Swarm topology — completely flattened.** `deploy.placement.constraints`
  (`node.labels.type==stateless` / `==stateful-arm64`), `replicas`,
  `update_config`, `rollback_config`, `restart_policy`, plus the full
  Traefik label sets on every service
  (`traefik.http.routers.solectrus-websecure.rule=Host(...)`, TLS
  cert-resolvers, middleware chains, port mappings) — all dropped. HELIOS
  doesn't model Swarm. First fixture to exercise a Swarm donor.
- **Reverse-proxy and network setup gone.** `traefik-public` external
  network, per-service `hostname: *.${APP_HOST}`, `links:` directives, and
  `ulimits.nofile` on the dashboard service all stripped.
- **S3 backup credentials silently lost.** Donor has populated
  `AWS_ACCESS_KEY=my-aws-access-key`, `AWS_SECRET_KEY=my-aws-secret-key`,
  `S3_REGION=eu-central-1`, `S3_BUCKET=solectrus`, plus
  `S3_PREFIX=postgres_backup`, `SCHEDULE=@daily`, and `CRON=0 2 * * *`.
  HELIOS renames `AWS_ACCESS_KEY` → `AWS_ACCESS_KEY_ID` and
  `AWS_SECRET_KEY` → `AWS_SECRET_ACCESS_KEY` and emits both as **empty**
  values in the exported `.env`, alongside empty `AWS_REGION` /
  `AWS_BUCKET`. Schedule, region, and prefix all revert to defaults. User
  must re-enter all S3 secrets via the HELIOS UI after import.
- **Custom `command:` overrides dropped.** InfluxDB ran with explicit
  `influxd run --bolt-path /var/lib/influxdb2/influxd.bolt --engine-path
  /var/lib/influxdb2/engine --store disk`; Redis ran with `--appendonly no
  --maxmemory 500mb --maxmemory-policy allkeys-lru`. Both replaced by
  image defaults.
- **Inverter `_4` and `_5` and custom-power slots `_03..05`, `_07`,
  `_10..20`** referenced in compose but blank or absent in `.env` —
  silently dropped on re-export.
- **Referenced-but-undefined env vars dropped:** `LOCKUP_CODEWORD`,
  `SKIP_BROWSER_CHECK`, `RUBY_YJIT_ENABLE=1` (inline literal),
  `INFLUX_SENSOR_HEATPUMP_LEAVING_TEMP`, `INFLUX_SENSOR_HEATPUMP_SCORE`,
  `INFLUX_SENSOR_CAR_MILEAGE`, `ELECTRICITY_PRICE`, `FEED_IN_TARIFF`. The
  last two are listed in `LEGACY_CONSUMED_ENV_KEYS`; the others go through
  the standard "no value, no entry" path.
- **`INFLUX_PORT=8086` / `INFLUX_SCHEMA=http`** in `.env` — dropped on
  re-export because HELIOS uses internal `influxdb` service-network
  addressing for the dashboard, ingest, and power-splitter.
- **`INFLUXDB_VOLUME_PATH` and `INFLUXDB_BACKUP_VOLUME_PATH` preserved as
  unmanaged.** The InfluxDB data path is also captured as
  `influxdb.volume_path` (re-emitted as `${INFLUX_VOLUME_PATH}` on export);
  the unmanaged copies survive the round-trip because HELIOS doesn't
  recognize the donor's non-canonical names.

## Round-trip stabilizer

- **No `INFLUX_PASSWORD` in donor `.env`** — the user runs InfluxDB
  against a pre-existing volume (`${INFLUXDB_VOLUME_PATH}:/var/lib/influxdb2`)
  and manages credentials outside Docker, so `DOCKER_INFLUXDB_INIT_*` is
  absent from both compose and env. A placeholder
  `INFLUX_PASSWORD=my-influx-admin-password` was added to `.env.bak` to
  keep the round-trip deterministic; without it the importer falls back
  to `SecureRandom.alphanumeric(32)` and the export diff is unstable.
  HELIOS re-export emits the full `DOCKER_INFLUXDB_INIT_*` block —
  harmless against an already-initialized volume.
