# user4

Real-world `docker-compose.yml` + `.env` from a SOLECTRUS user running an
older SENEC stack with five Shelly devices, a multi-plane forecast.solar
setup, and a power-splitter pointing at a different DB hostname than the
DB service it depends on. Anonymized but otherwise untouched.

## Highlights

- **Legacy compose filename `docker-compose.yml`** — same pre-Compose-Spec
  filename as user3; the importer must resolve `Compose::FILENAMES` lazily
  to find the `.yml` variant.
- **Legacy service names `app:` and `db:`** — the dashboard service is
  called `app:` (like user1) and the PostgreSQL service is called `db:`,
  not the canonical `dashboard:` / `postgresql:`. Both are aliased via
  `SERVICE_IMAGE_PREFIXES` and re-exported under the new names.
- **Stale `solectrus:1-0-beta` image tag** — preserved verbatim instead of
  being normalized to a release tag, so the user can decide when to upgrade.
- **`postgres:15-alpine`** — old PostgreSQL major version preserved instead
  of being bumped to the HELIOS default.
- **Five shelly-collector services with numeric suffixes** — the source
  compose declares `shelly-collector-001` through `-005`, each parameterized
  by `SHELLY_HOST_001..005` / `INFLUX_MEASUREMENT_SHELLY_001..005`. The
  importer merges all five into a single managed `shelly-collector` with
  comma-joined `SHELLY_HOST` and `INFLUX_MEASUREMENT` lists. (user3
  exercises the same pattern with named suffixes; this one keeps the numeric
  variant honest.)
- **Twenty `INFLUX_SENSOR_CUSTOM_POWER_NN` slots** — only `_01..05` are
  populated (the five Shellys); `_06..20` are blank and dropped on
  re-export rather than being carried forward as empty mappings.
- **Power-splitter wired to `DB_HOST=postgresql` while the DB service is
  named `db`** — a latent misconfiguration in the source: the power-splitter
  tries to talk to a hostname that doesn't exist on the bridge network. The
  importer doesn't try to fix this; it just renames `db:` → `postgresql:`
  on re-export, which incidentally repairs the bug. Documents that a
  config-aware importer can heal user typos as a side effect of normalizing
  service names.
- **`INFLUX_SENSOR_INVERTER_POWER` referenced in compose but absent from
  `.env`** — only `_1`, `_2`, `_3`, `_4`, `_5` are defined. With
  `INFLUX_MEASUREMENT_PV=SENEC` set, `LegacySensorAdapter` synthesizes
  `inverter_power` from the fallback table even though the user never set
  it explicitly. `_4` / `_5` are blank and dropped.
- **`INFLUX_SENSOR_WALLBOX_POWER=` blank, respected as user opt-out** —
  donor has no wallbox and explicitly blanks the slot. Even with
  `INFLUX_MEASUREMENT_PV=SENEC` flipping the importer into legacy mode,
  `LegacySensorAdapter` skips any sensor whose `INFLUX_SENSOR_*` key is
  present in the dashboard env (regardless of value), so the blank entry
  is treated as a deliberate "no thanks" and dropped on re-export instead
  of being resurrected from the fallback table. Same treatment as
  `INFLUX_SENSOR_CAR_BATTERY_SOC=` below.
- **`INFLUX_SENSOR_CAR_BATTERY_SOC=` blank** — also dropped, both because
  the entry is empty (user opt-out, same rule as wallbox above) and
  because the sensor isn't in the legacy fallback table to begin with.
- **forecast.solar with four planes declared, only two active** —
  `FORECAST_0_*` and `FORECAST_1_*` populated, `_2_*` and `_3_*`
  commented out. `FORECAST_CONFIGURATIONS=2` matches reality, so HELIOS
  imports `forecast_roofs: '2'` and only emits the active two on re-export.
- **Negative azimuth `FORECAST_0_AZIMUTH=-115`** — round-trips as the
  quoted string `'-115'` in YAML (leading `-` triggers the quote).
- **Inline `INFLUX_TOKEN=${INFLUX_ADMIN_TOKEN}` on the power-splitter** —
  a third token-routing variant alongside the dashboard's
  `INFLUX_TOKEN_READ` and the collectors' `INFLUX_TOKEN_WRITE`. All three
  values happen to be identical, so consolidation to a single
  `INFLUX_TOKEN` on re-export is lossless.
- **`POWER_SPLITTER_INTERVAL=300`** — donor's non-default 5-minute
  cadence preserved under `power_splitter.interval` (same shape as
  user3).
- **Watchtower with `command: --scope solectrus --cleanup`** — no
  `WATCHTOWER_*` env vars; HELIOS rewrites the service to use
  `WATCHTOWER_POLL_INTERVAL=86400` (default) and drops the command.
- **`INFLUX_MEASUREMENT_FORECAST=Forecast` defined twice in `.env`** —
  once in the InfluxDB block and again in the Forecast block. The
  importer tolerates the redefinition; only the canonical name survives
  on re-export.
- **`## version: '3.7'` double-hash top-level comment** in compose —
  the user kept an old `version:` directive commented out. Comments are
  dropped on re-export (acceptable per CLAUDE.md); the importer must not
  choke on the leading `##`.
- **Commented-out sensor line `# INFLUX_SENSOR_INVERTER_POWER=...`** in
  `.env` — a leftover note from manual configuration. Ignored by the
  parser, dropped on re-export.
- **`ELECTRICITY_PRICE=0.11` / `FEED_IN_TARIFF=0.11`** — legacy
  dashboard-only env vars, today managed via the UI as historical prices.
  Listed in `LEGACY_CONSUMED_ENV_KEYS` so they're silently dropped on
  import rather than carried forward as `_unmanaged.env_vars` noise.
- **Trailing tabs/spaces on label values** — `shelly-collector-002`
  and `-004` end with stray whitespace, `-005` has a tab between
  `solectrus` and end-of-line. YAML round-trips these without complaint.
- **`dozzle` log viewer** — unrecognized service preserved verbatim under
  `_unmanaged.services.dozzle` (same as user3).
