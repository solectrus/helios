# user26

Real-world `docker-compose.yml.bak` + `.env.bak` from a SOLECTRUS user
running one of the **oldest stack layouts** in the corpus: a pre-Traefik
Compose 3.7 file (`# version: "3.7"`, per-service `links:`,
`depends_on:` lists, a published `ports: 3000:3000`, and a `nc`-based
`healthcheck`) with a **legacy local SENEC collector** and a single
`forecast.solar` plane. The donor stripped every secret and the plant
coordinates to empty strings before sharing; these were refilled with
placeholder values (`my-*` secrets, coordinates blunted to one decimal)
so the stack is realistic and round-trips deterministically. Otherwise
untouched, including a pair of stray `B` lines the donor left in the
Redis section of the `.env`.

Every image is first-party, so `Import::CompatibilityCheck` accepts the
stack and it round-trips. The fixture exercises several import paths that
no prior snapshot combines:

- **Oldest InfluxDB pin in the corpus, preserved tag-exact.** The donor
  runs `influxdb:2.5-alpine` (every other fixture is 2.7/2.8/2-alpine,
  one 2.1.1). HELIOS keeps the exact `influxdb:2.5-alpine` tag rather
  than bumping it, and replaces the donor's hand-written
  `command: influxd run … --store disk` (plus the commented-out
  `ports: 8086`) with its canonical InfluxDB service.
- **Bare legacy `senec-collector` → full canonical sensor map.** The
  donor collector carries only `SENEC_SCHEMA/HOST/INTERVAL` — no
  `SENEC_ADAPTER`, no `INFLUX_SENSOR_*` mappings. HELIOS infers
  `adapter: local`, `version: v3`, and materializes the complete SENEC
  sensor set (`inverter_power`, `grid_power_plus/minus`, `bat_*`,
  `wallbox_charge_power`, `case_temp`, `current_state[_ok]`, …) that the
  legacy collector wrote by fixed convention.
- **Single-plane forecast.solar.** Declination/azimuth/kWp are set and
  the (refilled) coordinates round-trip as `forecast_roofs: '1'`.
- **`INFLUX_ADMIN_TOKEN` and both traffic tokens share one value.** The
  donor's comment spells out the "one token for read and write" pattern;
  HELIOS folds it into `token_admin`/`token_readwrite`/`token_write`/
  `token_read` all pointing at the same secret.
- **Noise the importer discards.** A commented-out `renault-collector`
  block and the two stray `B` lines in the donor `.env` are dropped —
  the canonical `.env` is regenerated from scratch, so non-`KEY=VALUE`
  junk does not survive (and does not break the parse).
- **Managed services HELIOS adds on adoption.** The donor ships no
  `power-splitter`, `watchtower`, or `helios` service, nor `TZ` /
  `CURRENCY` / `WEB_CONCURRENCY`; all appear in the exported stack as
  managed defaults.
