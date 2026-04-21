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
│  │  ┌──────────┐ ┌────────────┐ ┌──────────┐ ┌─────────────┐  │  │
│  │  │  HELIOS  │ │ Watchtower │ │ InfluxDB │ │  SOLECTRUS  │  │  │
│  │  │  :3999   │ │ (updates)  │ │  :8086   │ │  Dashboard  │  │  │
│  │  └────┬─────┘ └──────┬─────┘ └──────────┘ │   :3000     │  │  │
│  │       │              │                    └─────────────┘  │  │
│  │       │              │        ┌──────────┐ ┌─────────────┐ │  │
│  │       │              │        │ Postgres │ │    Redis    │ │  │
│  │       │              │        │  :5432   │ │   :6379     │ │  │
│  │       │              │        └──────────┘ └─────────────┘ │  │
│  │       │ manages      │ updates                             │  │
│  │       ▼              ▼                                     │  │
│  │  ┌─────────────────────────┐                               │  │
│  │  │     compose.yaml        │                               │  │
│  │  │         .env            │                               │  │
│  │  └─────────────────────────┘                               │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  /var/run/docker.sock ◄─── HELIOS + Watchtower access Docker API │
└──────────────────────────────────────────────────────────────────┘
```

---

## HELIOS Internal Storage

All user-facing configuration is stored in a single `config.yaml` file (see [ADR-0009](../adr/0009-configuration-model.md)) — there are no Active Record tables for application data. The `primary` SQLite database exists only to satisfy Rails' default setup and is currently empty.

| File              | Purpose                                                              |
| ----------------- | -------------------------------------------------------------------- |
| `config.yaml`     | All user configuration (singletons: system, senec, mqtt, sensors, …) |
| `primary.sqlite3` | Rails primary DB (empty; reserved for future use)                    |
| `cable.sqlite3`   | SolidCable (Turbo Streams / Action Cable pub-sub)                    |

The admin password is stored in `config.yaml` under `system.admin_password` (bcrypt hash), not in a separate `admins` table.

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

---

## Install Script

See [`install.sh`](../../install.sh) in the repository root.

**Prerequisites:** Docker and Docker Compose must be installed.

The script checks prerequisites, creates a minimal `compose.yaml` with only HELIOS, and starts the stack. The vanity URL `solectrus.de/install.sh` can redirect to the raw file on GitHub.
