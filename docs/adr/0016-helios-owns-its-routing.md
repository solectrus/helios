# ADR-0016: HELIOS Owns the Traefik Routing of Its Own Services

Supersedes [ADR-0015](0015-service-overrides.md).

## Context

ADR-0015 added a `service_overrides` section so that an import could rescue Traefik labels HELIOS does not generate. The exporter appended those labels to the generated service, and the routing of a service that brought its own router stayed with the import.

The mechanism did not hold what it promised. Four fixtures carried a `service_overrides` section, and this is what they held:

| Fixture                                              | Content                                                     | Effect  |
| ---------------------------------------------------- | ----------------------------------------------------------- | ------- |
| `real_world/user23`, `v1_4_3_user23`, `multi_shelly` | A redirect middleware plus `routers.redirs.middlewares=...` | None    |
| `with_custom_traefik`                                | A rate-limit middleware, and a router for InfluxDB          | Partial |

The first row is the common shape, and it was broken by the import itself. The donor stacks sent port 80 to HTTPS with three labels: a rule, an entrypoint and a middleware. The importer stripped the first two, because HELIOS writes a router for the dashboard itself. The third one stayed. A router without a rule is not a router, so the redirect stopped working and the generated file carried the remains.

The rate-limit middleware of the second row hung on no router, in the donor stack already. What was left is one router for InfluxDB, and HELIOS can write that one itself: the host is the one it routes the stack at, the entrypoint is in the adopted command, and so is the resolver.

The mechanism therefore preserved nothing that worked, and it cost a branch in every place that asks how a service is routed.

## Decision

HELIOS writes the Traefik routing of its own four services: dashboard, InfluxDB, Ingest and HELIOS itself. Three parts follow from that.

**The export owns the entrypoints of those services.** The entrypoints named `influxdb`, `ingest` and `helios` are HELIOS's. It adds the one a routed service needs, corrects a port that does not match the configuration, and drops one whose service it no longer routes, together with the port that entrypoint published. Every other entrypoint of an adopted command stays verbatim, the resolver and the ACME options included.

**The export writes the HTTPS redirect.** An adopted command arrives without `--entrypoints.web.http.redirections.entrypoint.to=websecure`, because the older SOLECTRUS setup wrote the redirect as a middleware. HELIOS adds the flag, so port 80 answers again.

**The import refuses what the export would overwrite.** `Import::CompatibilityCheck` reads the Traefik labels of every managed service and refuses the import when it finds one HELIOS will not write again. Two shapes count: a label outside the set HELIOS generates, and a router whose rule names another address than the one the stack answers at. A router that only sends a request on to HTTPS is accepted, because HELIOS does the same on the entrypoint.

The `service_overrides` section goes. Migration 008 deletes it.

## Consequences

**Positive:**

- One answer to "how is this service routed", instead of one per import shape. `traefik_managed_routing?` asks whether a managed Traefik runs, and nothing else.
- The redirect of the common donor shape works again, and the generated file no longer carries a router that Traefik refuses.
- A port that an entrypoint left behind is closed instead of staying open on nothing.
- A stack HELIOS cannot reproduce is named at the import, while the user can still open it and read it. Before, it imported and lost its routing later, when the next save rewrote `compose.yaml`.

**Negative:**

- A stack with a middleware HELIOS does not know, such as a rate limit or basic auth, cannot be imported. The user removes the labels first, or runs the proxy beside the stack in the external mode, where HELIOS writes no routes at all. This is the trade the import gate already makes for a service whose image HELIOS does not know.
- A router name of the donor is not kept. HELIOS names the router after the service.
