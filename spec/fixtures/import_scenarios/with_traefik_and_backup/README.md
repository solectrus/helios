# with_traefik_and_backup

Stack with a Traefik reverse proxy and S3 backup sidecars for PostgreSQL and
InfluxDB. Verifies that these three are mapped to dedicated config blocks
(`reverse_proxy:`, `backup:`) rather than `_unmanaged`.

## Highlights

- **Traefik labels on the dashboard service** (`traefik.http.routers.dashboard.rule`,
  `certresolver=letsencrypt`, …) are the sole source for the
  `reverse_proxy.app_domain` (`solar.example.com`) and `letsencrypt_email` —
  the Traefik service itself carries no explicit domain config.
- **`postgresql-backup` → `backup.postgresql`** and **`influxdb-backup` →
  `backup.influxdb`**, with a shared AWS credential block
  (`aws_access_key_id`, `aws_secret_access_key`, `aws_region`, `aws_bucket`)
  promoted to the top of `backup:`.
- **Different cron schedules tolerated** (`SCHEDULE=@daily` for Postgres,
  `CRON=0 0 * * 0` for InfluxDB) — neither schedule appears in `config.yaml`
  (HELIOS defaults take over on export).
- **`sensors: {}`** — no sensor mappings are defined; the dashboard has only
  the base environment (`APP_HOST` missing, `FORCE_SSL=true`).
- Nothing ends up in `_unmanaged` — all six non-core services are recognised.
