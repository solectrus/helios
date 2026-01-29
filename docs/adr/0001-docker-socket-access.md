# ADR-0001: Docker Socket Access

## Status

Accepted

## Context

Helios needs to manage Docker containers: start/stop services, read logs, check health status. There are multiple ways to access Docker:

1. Docker Socket (`/var/run/docker.sock`)
2. Docker TCP API (requires extra configuration)
3. Docker CLI only (limited functionality)

## Decision

Use Docker Socket for all Docker operations.

## Consequences

**Positive:**

- Industry standard (used by Portainer, Watchtower, etc.)
- Full Docker API access
- No additional configuration required
- Works with Docker Compose operations

**Negative:**

- Requires mounting socket into container
- Requires appropriate permissions (docker group or root)
- Security consideration: container has full Docker access

**Mitigations:**

- Helios is the management layer, so full access is intentional
- LAN-only access reduces attack surface
