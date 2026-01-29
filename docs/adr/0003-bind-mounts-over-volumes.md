# ADR-0003: Bind Mounts over Docker Volumes

## Status

Accepted

## Context

Docker offers two main options for persistent data:

1. Named volumes (`postgresql_data:`)
2. Bind mounts (`./postgresql:/var/lib/postgresql/data`)

## Decision

Use bind mounts (local directories) for all persistent data instead of Docker volumes.

## Consequences

**Positive:**

- Data is visible and accessible on the host filesystem
- Easy to backup with standard tools (rsync, tar, etc.)
- Easy to inspect and debug
- Portable: just copy the entire directory
- User can see exactly where data is stored

**Negative:**

- Slightly more complex compose.yaml
- Requires directory creation on first run
- File permissions may need attention

**Directory structure:**

```
/opt/solectrus/
├── helios/      # Helios SQLite database
├── postgresql/  # PostgreSQL data
├── redis/       # Redis data
└── influxdb/    # InfluxDB data
```
