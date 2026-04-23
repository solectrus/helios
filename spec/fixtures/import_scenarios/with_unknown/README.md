# with_unknown

Baseline stack with two **completely unrelated** sidecar services (`dozzle`,
`nginx`) that have nothing to do with SOLECTRUS. Verifies that truly foreign
services survive a round-trip unchanged.

## Highlights

- **`dozzle` and `nginx` preserved verbatim** under `_unmanaged.services` with
  their full compose definition (image, ports, volumes, environment) — nothing
  gets dropped or rewritten.
- **nginx references a custom variable** `NGINX_CUSTOM_SETTING=${MY_CUSTOM_VAR}`.
  The literal assignment becomes an `env_values: { MY_CUSTOM_VAR: custom-value }`
  entry on the service; the `environment:` list keeps the `${MY_CUSTOM_VAR}`
  reference intact.
- **`dozzle` has an empty environment list** (`environment: []`) — preserved
  as-is rather than omitted.
- **`sensors: {}`** and no optional SOLECTRUS blocks (forecast, senec, shelly,
  mqtt) — the test focuses purely on unmanaged-service handling.
- Contrast with `with_senec_charger` / `with_tibber`: those services are
  SOLECTRUS-adjacent; `dozzle` / `nginx` are third-party.
