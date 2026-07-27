# ADR-0002: SQLite for Internal Storage

## Context

HELIOS needs persistence for Rails infrastructure (WebSocket messages) and for operational records that accumulate over time (backup history, background runner state). Configuration itself stays file-based (see ADR-0009).

## Decision

Use SQLite for Rails infrastructure and operational records:

| Database (production)          | Purpose                                        | Managed by |
| ------------------------------ | ---------------------------------------------- | ---------- |
| `/data/helios/primary.sqlite3` | Operational records (`backups`, `runner_logs`) | Rails      |
| `/data/helios/cable.sqlite3`   | WebSocket message transport                    | SolidCable |

In development and test these live under `storage/` (e.g. `storage/development.sqlite3`).

Background jobs run in-process (no separate queue) — see [ADR-0012](0012-in-process-background-jobs.md).

Everything the user configures is stored elsewhere:

| Data             | Storage                  |
| ---------------- | ------------------------ |
| Configuration    | `config.yaml` (ADR-0009) |
| User preferences | Browser cookies          |

The rule of thumb: if a user edits it, it belongs in `config.yaml`; if HELIOS produces it while running, it belongs in the database.

## Consequences

**Positive:**

- No additional container required
- Lightweight, suitable for Raspberry Pi
- Configuration changes need no database migration (`config.yaml` has its own, see ADR-0014)
- Configuration is human-readable and easy to backup

**Negative:**

- Multiple SQLite files to persist (via bind mount)

**Location:**
In production both SQLite files live in `/data/helios/` inside the container, which is bind-mounted to the stack directory on the host. No separate volume is required.
