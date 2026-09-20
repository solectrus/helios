# v1_4_3_senec_cloud

A single-host production stack, donated as a support bundle from HELIOS
v1.4.3 on 2026-09-20. The `config.yaml` carries schema version 5.

What the scenario covers:

- SENEC cloud adapter, v4, request mode `full`
- pvnode forecast with four roofs, paid plan, extra parameters
- Shelly cloud with 17 devices, one measurement per device, mode
  `essential`
- Managed Traefik with an extra entrypoint for InfluxDB on port 8086
- A `service_overrides` entry that adds two labels to the dashboard
- No `system.currency`, so the export must fall back to the default

## Comparison against the donor stack

The `compose.yaml` that HELIOS produces today is byte-identical to the one
the donor runs. The `.env` differs in one entry: HELIOS no longer writes
`APP_DOMAIN`, because no service reads it. The Traefik labels carry the
domain as a literal.

The migration from schema 5 to schema 6 changes the version number only.
`system.app_host` stays, because it holds a public domain name.
