# collectors_only

Collector-only installation: just the SENEC, Shelly and MQTT collectors — **no**
dashboard, PostgreSQL, Redis or InfluxDB service. Data is written to an external
InfluxDB instance (`INFLUX_HOST=ingest.example.com`, `INFLUX_PORT=443`).

## Highlights

- **`deployment.mode: collectors_only`** — derived from the absence of the dashboard.
- **External InfluxDB** over HTTPS on port 443 (not the bundled `influxdb` container).
- **SENEC collector** in `local` mode against `senec.fritz.box`.
- **Shelly collector** with 11 devices via `SHELLY_HOST_*` variables and a shared
  `SHELLY_PASSWORD=secret`; `INFLUX_MODE=essential`.
- **MQTT collector** with 34 mappings (sparse `MAPPING_*` indices 1–37) for an
  Altherma heat pump (espaltherma), exercising `JSON_KEY`, `JSON_PATH` and
  complex `JSON_FORMULA` expressions (e.g. heat calculation and a derived
  `current_state`).
- Collector images use the `develop` tag.
