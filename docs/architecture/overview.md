# Architecture Overview

## Technology Stack

See [ADR-0007: Technology Stack](../adr/0007-technology-stack.md) for details and rationale.

---

## System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         Host System                              │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                     Docker Engine                          │  │
│  │                                                            │  │
│  │  ┌──────────┐     ┌────────────────────────────────────┐   │  │
│  │  │  HELIOS  │     │  Other stack services              │   │  │
│  │  │  :3999   │     │  (Dashboard, databases, collectors,│   │  │
│  │  │          │     │   Power-Splitter, Watchtower, …)   │   │  │
│  │  └────┬─────┘     └────────────────────────────────────┘   │  │
│  │       │                                                    │  │
│  │       │ manages                                            │  │
│  │       ▼                                                    │  │
│  │  ┌─────────────────────────┐                               │  │
│  │  │     compose.yaml        │                               │  │
│  │  │         .env            │                               │  │
│  │  └─────────────────────────┘                               │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  /var/run/docker.sock ◄─── HELIOS accesses Docker API            │
└──────────────────────────────────────────────────────────────────┘
```

---

## HELIOS Internal Storage

All user-facing configuration is stored in a single `config.yaml` file (see [ADR-0009](../adr/0009-configuration-model.md)) — no Active Record tables are involved. The `primary` SQLite database holds only operational records that HELIOS produces at runtime (see [ADR-0002](../adr/0002-sqlite-for-internal-storage.md)).

| File              | Purpose                                                              |
| ----------------- | -------------------------------------------------------------------- |
| `config.yaml`     | All user configuration (singletons: system, senec, mqtt, sensors, …) |
| `primary.sqlite3` | Operational records (`backups`, `runner_logs`)                       |
| `cable.sqlite3`   | SolidCable (Turbo Streams / Action Cable pub-sub)                    |

The admin password is stored in `config.yaml` under `system.admin_password` and mirrored to the generated `.env` as `ADMIN_PASSWORD`, since the Dashboard service needs the same value. It is not random: unless `ADMIN_PASSWORD` is supplied via the environment, it is derived deterministically from `secret_key_base` as `Digest::SHA256.hexdigest(secret_key_base)[0, 32]` (see [`ConfigSchema::SYSTEM_DEFAULTS`](../../app/models/config_schema.rb)). This way legacy stacks that pre-date the variable round-trip to the same value on every export instead of churning a fresh random one into `config.yaml`. Login comparison uses `ActiveSupport::SecurityUtils.secure_compare` (see [`Authentication`](../../app/controllers/concerns/authentication.rb) / [`SessionsController`](../../app/controllers/sessions_controller.rb)).

**Location:** `/data/helios/` inside the HELIOS container (bind-mounted from the stack directory on the host).

---

## Directory Structure

```
/opt/solectrus/              # Installation directory (host, mounted as /data)
├── compose.yaml             # Docker Compose file (managed by HELIOS)
├── .env                     # Environment variables (managed by HELIOS)
├── helios/                  # HELIOS state
│   ├── config.yaml          # User configuration (single source of truth)
│   ├── primary.sqlite3      # Rails primary DB (unused)
│   └── cable.sqlite3        # SolidCable
├── postgresql/              # PostgreSQL data (bind mount)
├── redis/                   # Redis data (bind mount)
└── influxdb/                # InfluxDB data (bind mount)
```

**Note:** All data directories are bind mounts (local folders), not Docker volumes. This makes backup and inspection easier.
