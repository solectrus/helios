# v1_4_3_forecast_solar

A single-host production stack on a Raspberry Pi, donated as a support
bundle from HELIOS v1.4.3 on 2026-09-20. The `config.yaml` carries schema
version 5.

What the scenario covers:

- SENEC cloud adapter, v3, request mode `full`
- forecast.solar with one roof
- Shelly local with a single device, excluded from house power
- Power splitter next to the dashboard
- No reverse proxy. The dashboard and InfluxDB publish their ports
  directly on the host
- No `system.app_host`, so the export must leave the dashboard without a
  public address
- No `system.currency`, so the export must fall back to the default

## Comparison against the donor stack

The `compose.yaml` and the `.env` that HELIOS produces today differ from
the ones the donor runs in one variable: `APP_HOST`. HELIOS v1.4.3 wrote
`APP_HOST=localhost` whenever the field was empty, and passed the name to
the dashboard. The dashboard reads `APP_HOST` as a CORS origin alone, and
a loopback name matches no request that CORS decides. HELIOS now writes
the variable only when the configuration names a routable address, and
the `compose.yaml` then omits it too.

The migration from schema 5 to schema 6 changes the version number only.
The configuration holds no `system.app_host` for it to clear.
