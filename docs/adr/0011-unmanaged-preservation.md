# ADR-0011: Preservation of Unmanaged Services and Env Vars

## Context

HELIOS is introduced into installations that already have a hand-written `compose.yaml` and `.env`. These files often contain:

- Custom services that HELIOS does not know about (e.g. `traefik`, a VPN sidecar, a custom exporter)
- Env vars that are not part of SOLECTRUS (e.g. operator-specific flags, external API keys)

If HELIOS regenerated `compose.yaml` and `.env` from scratch on every export, those customizations would be silently deleted on the first save. Users would lose trust — or worse, lose their setup.

## Decision

Keep a closed-world list of services and env-var keys that HELIOS owns (the "managed set"); everything else is preserved verbatim under a dedicated `_unmanaged` key in `config.yaml`.

- `MANAGED_SERVICES` and `MANAGED_ENV_KEYS` in [`UnmanagedDetector`](../../app/services/import/configuration_importer/unmanaged_detector.rb) are the single source of truth
- On import, services and env vars outside the managed set are moved into `config.yaml → _unmanaged`
- On export, `_unmanaged` content is merged back into the generated `compose.yaml` and `.env` without modification
- A second list (`INFRASTRUCTURE_ENV_KEYS`) names well-known SOLECTRUS env vars that HELIOS doesn't generate but also doesn't need to surface as "unmanaged"; these are suppressed to keep the import quiet
- Dynamic managed keys (per-sensor `INFLUX_SENSOR_*`, indexed forecast/pvnode vars, MQTT `MAPPING_N_*`) are computed at import time so they don't leak into `_unmanaged`

This pairs with ADR-0008 (file handling rules) — together they guarantee round-trip fidelity for anything HELIOS wasn't asked to manage.

## Consequences

**Positive:**

- Users can introduce HELIOS to an existing stack without losing customizations
- Traefik, custom containers, and operator-specific env vars survive every export
- The managed set is explicit and reviewable — no "magic" inclusion rules

**Negative:**

- Adding a new managed service/env var requires updating the lists, otherwise content that _was_ unmanaged suddenly becomes managed (and may conflict with manual edits)
- Unmanaged content is not validated by HELIOS — a broken custom service stays broken
- `_unmanaged` content is mostly opaque to the UI: unmanaged services can be permanently removed from the Services screen (`ServicesController#destroy` → `ServiceRemovalJob`), but editing or re-adding them still requires shell access to `config.yaml`
