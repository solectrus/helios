# v1_4_3_user23

A single-host production stack, donated as a support bundle from HELIOS
v1.4.3 on 2026-09-20. The `config.yaml` carries schema version 5.

Same donor as
[`import_scenarios/real_world/user23`](../../import_scenarios/real_world/user23/),
which holds the hand-maintained `compose.yaml` the same installation ran
before HELIOS took it over. The two together cover both directions for
one stack: the import that adopted it, and the export that rebuilds it
from the file HELIOS wrote. The domain is masked differently in each,
because each bundle was anonymized on its own.

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
`system.app_host` stays, because it holds a public domain name. The migration
to schema 7 folds `reverse_proxy.app_domain` onto it: both named the same
machine, and the domain wins. `reverse_proxy` keeps `mode: internal` alone.
