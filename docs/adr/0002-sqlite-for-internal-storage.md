# ADR-0002: SQLite for Rails Infrastructure

## Context

HELIOS needs persistence for Rails infrastructure (WebSocket messages) but stores no application data in the database. All business data is file-based (see ADR-0009).

## Decision

Use SQLite exclusively for Rails infrastructure:

| Database (production)          | Purpose                        | Managed by |
| ------------------------------ | ------------------------------ | ---------- |
| `/data/helios/primary.sqlite3` | Primary (unused, empty schema) | Rails      |
| `/data/helios/cable.sqlite3`   | WebSocket message transport    | SolidCable |

In development and test these live under `storage/` (e.g. `storage/development.sqlite3`).

Background jobs run in-process (no separate queue) — see [ADR-0012](0012-in-process-background-jobs.md).

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
In production both SQLite files live in `/data/helios/` inside the container, which is bind-mounted to the stack directory on the host. No separate volume is required.
