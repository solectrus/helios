# ADR-0005: Watchtower for Automatic Updates

## Status

Accepted

## Context

SOLECTRUS containers need to be updated when new versions are released. Options:

1. Manual updates (user runs `docker compose pull && docker compose up -d`)
2. HELIOS checks for updates and applies them
3. Watchtower container handles updates automatically

## Decision

Use Watchtower (`nickfedor/watchtower:latest`) for automatic container updates.

## Consequences

**Positive:**

- Automatic updates without user intervention
- Updates all containers including HELIOS itself
- Well-established tool, battle-tested
- No custom update logic needed in HELIOS
- Fork includes additional features

**Negative:**

- Additional container in the stack
- Less control over update timing
- Potential for breaking changes with `latest` tag

**Mitigations:**

- Own services use `latest` (intentional, Watchtower updates them)
- Third-party services pin major version (e.g., `postgres:18-alpine`)
- Optional "Update now" button in HELIOS for manual trigger

**Note:** Watchtower is not included in MVP, but planned for later phases.
