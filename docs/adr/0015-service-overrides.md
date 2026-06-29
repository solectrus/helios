# ADR-0015: Generic Service Overrides for Managed Services

## Context

HELIOS rebuilds managed services (`dashboard`, `mqtt-collector`, `influxdb`, …) from opinionated templates on every export (ADR-0009). Anything outside the template's known schema is silently dropped on round-trip. Real-world stacks routinely diverge on small but operationally important keys:

- Dashboard's Traefik router referencing a custom rate-limit middleware via extra `traefik.http.middlewares.*` labels (user6).
- Custom host port mapped on `influxdb` for an external Grafana scrape.
- An extra bind-mount on `mqtt-collector` for a custom CA bundle.
- A few additional environment variables on `dashboard` consumed by a custom theme.

Two existing escape hatches partially cover this:

- `_unmanaged.services` (ADR-0011) — only for services HELIOS does **not** recognize. Doesn't help for divergences on managed services, because HELIOS still owns the service definition.
- `reverse_proxy.service_labels` — narrowly scoped pass-through for per-service `traefik.*` labels, added in 1d9e44f / af9323b. Solves one specific shape; every new shape (privileged, ports, cap_add, …) currently requires its own bespoke field, extractor, and exporter branch.

This doesn't scale: each new fixture surfaces a new divergence, and HELIOS keeps growing per-feature plumbing instead of a generic mechanism.

## Decision

Introduce a single `service_overrides` section in `config.yaml`, keyed by managed-service name, with a fixed allowlist of compose keys. The exporter deep-merges these over the generated service hash; the importer captures any allowlisted divergence into the same structure.

```yaml
service_overrides:
  mqtt-collector:
    privileged: true
  dashboard:
    labels:
      - 'traefik.http.middlewares.test-ratelimit.ratelimit.average=100'
      - 'traefik.http.middlewares.test-ratelimit.ratelimit.burst=200'
  influxdb:
    ports:
      - '8087:8086'
```

### Allowlist

Deliberately narrow initial allowlist, covering the operationally relevant divergences observed in real-world fixtures:

| Key           | Merge strategy                         |
| ------------- | -------------------------------------- |
| `labels`      | Array concat (dedupe)                  |
| `ports`       | Array concat (dedupe)                  |
| `volumes`     | Array concat (dedupe)                  |
| `environment` | Hash merge (override wins on conflict) |

Excluded on purpose: `privileged`, `cap_add`, `sysctls`, `tmpfs`, `restart`. These are either security-sensitive or rarely intentional (user6's `privileged: true` on `mqtt-collector` is most likely an accidental leftover, not a deliberate operational choice). Adding any of them to the allowlist requires a follow-up ADR with a concrete real-world need, not speculative coverage.

Anything outside the allowlist is rejected at config-load time with a clear validation error and dropped at import time with a one-line warning surfaced in the import-report banner. The allowlist may grow in future ADRs; it must never silently widen.

### Conflicts with HELIOS-generated values

For collections (`labels`, `ports`, `volumes`), the override is appended; collisions on container-port (`ports`) or label-key (`labels`) are resolved override-wins to keep the model predictable. For `environment`, conflicting keys are also override-wins. The dashboard's HELIOS-generated Traefik labels are always emitted first and must not be removable via `service_overrides` — middleware additions are append-only.

### Importer

A new `ServiceOverridesExtractor` runs alongside the per-section extractors and captures `traefik.*` labels per managed service:

1. For each managed service present in the source compose, take its `traefik.*` labels (read from raw YAML to preserve donor ordering).
2. The dashboard is special-cased: labels that match HELIOS's regenerated routing pattern (`traefik.enable`, `traefik.http.routers.<n>.rule`/`entrypoints`/`tls(.certresolver)`, `traefik.http.services.<n>.loadbalancer.server.port`) are stripped, since HELIOS owns dashboard routing. The remainder (typically `traefik.http.middlewares.*`) survives as a dashboard override.
3. Other managed services keep their `traefik.*` labels verbatim.

This subsumes the previous `reverse_proxy.service_labels` carrier, which is removed outright — HELIOS has no installed base depending on the old key, so no schema migration is needed.

Other allowlist keys (`ports`, `volumes`, `environment`) are not extracted automatically yet — the importer's structural-diff against each service template is non-trivial, and no real-world fixture currently demands it. Users add these via the UI when needed.

### Exporter

`Compose#build_service_hash` performs the deep merge after `extra_traefik_labels_for` and `WATCHTOWER_LABEL` injection but before `default_logging`. The merge is a small dispatcher over the allowlist (one method per strategy), not a generic recursive merge — explicit semantics beat clever code here.

### UI

A per-service "Erweitert" disclosure in the service detail view exposes a key/value editor for the allowlist, hidden by default. No survey-driven configuration. This is opt-in, advanced, and clearly labeled as user-owned ("HELIOS validates the syntax but not the effect").

## Consequences

**Positive:**

- New compose-key divergences no longer require schema/extractor/exporter changes — only an allowlist entry plus tests.
- Round-trip fidelity becomes the default for the documented allowlist; the dashboard `test-ratelimit` middleware loss in user6 is covered immediately. The `privileged: true` divergence on `mqtt-collector` remains intentionally dropped — see "Allowlist" above.
- `reverse_proxy.service_labels` is retired in favour of the general mechanism; no installed base depended on it.
- Power users can model complex setups (extra ports, capabilities, middlewares) without HELIOS having to "understand" them.

**Negative:**

- Support burden shifts: a broken stack after a manually added port collision or volume mount is the user's problem, not HELIOS's. Mitigated by hiding the UI behind an "advanced" disclosure, a clear ownership note, and the deliberately narrow allowlist.
- Allowlist drift: each new entry is a small policy decision. Mitigated by requiring an ADR amendment (or a new ADR) to extend the allowlist, not just a code change.
- Override values are not introspected — HELIOS won't warn that two overrides bind the same host port across services, for example. Acceptable: docker compose itself surfaces these at `up` time.
