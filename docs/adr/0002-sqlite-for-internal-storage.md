# ADR-0002: SQLite for Rails Infrastructure

## Status

Accepted (updated to reflect current usage)

## Context

Helios needs persistence for Rails infrastructure (background jobs, WebSocket messages) but stores no application data in the database. All business data is file-based (see ADR-0009).

## Decision

Use SQLite exclusively for Rails infrastructure:

| Database                           | Purpose                        | Managed by |
| ---------------------------------- | ------------------------------ | ---------- |
| `storage/production.sqlite3`       | Primary (unused, empty schema) | Rails      |
| `storage/production_queue.sqlite3` | Background job queue           | SolidQueue |
| `storage/production_cable.sqlite3` | WebSocket message transport    | SolidCable |
| `storage/production_cache.sqlite3` | Cache store                    | SolidCache |

Application data is stored elsewhere:

| Data             | Storage                  |
| ---------------- | ------------------------ |
| Configuration    | `config.yaml` (ADR-0009) |
| User preferences | Browser cookies          |

## Consequences

**Positive:**

- No additional container required
- Lightweight, suitable for Raspberry Pi
- No database migrations needed for application features
- Application data is human-readable and easy to backup

**Negative:**

- Multiple SQLite files to persist (via bind mount)

**Location:**
`/app/storage/` (persisted via bind mount to `./helios/`)
