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
│  │  │  Helios  │ │ Watchtower │ │ InfluxDB │ │  SOLECTRUS  │  │  │
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
│  /var/run/docker.sock ◄─── Helios + Watchtower access Docker API │
└──────────────────────────────────────────────────────────────────┘
```

---

## Helios Internal Storage

Helios uses SQLite for its own data:

| Table            | Purpose                                                              |
| ---------------- | -------------------------------------------------------------------- |
| `admins`         | Admin password hash (authentication)                                 |
| `configurations` | Setup state, flags, and unmanaged services/env vars (JSON blob)      |
| `chapters`       | Configuration sections: system, devices, inverter, etc. (JSON blobs) |

**Location:** `/app/storage/` (inside container, persisted via bind mount to `./helios/`)

---

## Directory Structure

```
/opt/solectrus/              # Installation directory (host)
├── compose.yaml             # Docker Compose file (managed by Helios)
├── .env                     # Environment variables (managed by Helios)
├── helios/                  # Helios data (bind mount for /app/storage)
│   ├── production.sqlite3   # Primary database
│   ├── production_queue.sqlite3  # SolidQueue database
│   └── production_cable.sqlite3  # SolidCable database
├── postgresql/              # PostgreSQL data (bind mount)
├── redis/                   # Redis data (bind mount)
└── influxdb/                # InfluxDB data (bind mount)
```

**Note:** All data directories are bind mounts (local folders), not Docker volumes. This makes backup and inspection easier.

---

## Install Script

See [`install.sh`](../../install.sh) in the repository root.

**Prerequisites:** Docker and Docker Compose must be installed.

The script checks prerequisites, creates a minimal `compose.yaml` with only Helios, and starts the stack. The vanity URL `solectrus.de/install.sh` can redirect to the raw file on GitHub.
