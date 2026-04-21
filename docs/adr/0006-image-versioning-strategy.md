# ADR-0006: Image Versioning Strategy

## Context

Docker images can be tagged in different ways:

- `latest` (always newest)
- Semantic version (`1.2.3`)
- Major version (`1`)
- Major.minor (`1.2`)

Different strategies have different trade-offs for stability vs. freshness.

## Decision

Use different strategies for own services vs. third-party services:

| Service Type       | Tag Strategy         | Example                              |
| ------------------ | -------------------- | ------------------------------------ |
| SOLECTRUS services | `latest`             | `ghcr.io/solectrus/solectrus:latest` |
| Third-party        | Major version pinned | `postgres:18-alpine`                 |

During development, some SOLECTRUS services may temporarily use the `develop` tag instead of `latest` to track the development branch. This is switched to `latest` before release.

## Consequences

**Positive:**

- Own services always get latest features and fixes
- Third-party services protected from breaking changes
- Minor/patch updates still apply to third-party
- Watchtower can update everything safely

**Negative:**

- Own services may receive breaking changes (acceptable, we control them)
- Major version bumps for third-party require manual intervention

**Image tags:**

| Service        | Image                                     |
| -------------- | ----------------------------------------- |
| Dashboard      | `ghcr.io/solectrus/solectrus:latest`      |
| HELIOS         | `ghcr.io/solectrus/helios:latest`         |
| Power-Splitter | `ghcr.io/solectrus/power-splitter:latest` |
| PostgreSQL     | `postgres:18-alpine`                      |
| Redis          | `redis:8-alpine`                          |
| InfluxDB       | `influxdb:2-alpine`                       |
| Watchtower     | `nickfedor/watchtower:latest`             |
