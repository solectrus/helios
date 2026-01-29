# ADR-0002: SQLite for Internal Storage

## Status

Accepted

## Context

Helios needs to store internal state:

- Admin password hash
- Setup completion status
- Service registry (which services Helios manages)
- Configuration (JSON blob with general settings, sensor mappings, service options)

Options considered:

1. PostgreSQL (already in stack)
2. SQLite (embedded)
3. File-based (JSON/YAML)

## Decision

Use SQLite for Helios internal storage.

## Consequences

**Positive:**

- No additional container required
- Lightweight, suitable for Raspberry Pi
- Rails has excellent SQLite support
- Single file, easy to backup
- No network dependencies

**Negative:**

- Cannot share database with SOLECTRUS Dashboard
- Limited concurrent write performance (not an issue for Helios)

**Location:**
`/app/data/helios.sqlite3` (persisted via bind mount to `./helios/`)
