# ADR-0003: Bind Mounts over Docker Volumes

## Context

Docker offers two main options for persistent data:

1. Named volumes (`postgresql_data:`)
2. Bind mounts (`./postgresql:/var/lib/postgresql`)

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
├── helios/      # HELIOS SQLite database
├── postgresql/  # PostgreSQL data
├── redis/       # Redis data
└── influxdb/    # InfluxDB data
```

## PostgreSQL container path

The container-side mount point for PostgreSQL is **version-specific** — the
official `postgres` image moved its `VOLUME` between major versions:

| Postgres image          | `PGDATA` default                | Image `VOLUME`             |
| ----------------------- | ------------------------------- | -------------------------- |
| `postgres:17` and older | `/var/lib/postgresql/data`      | `/var/lib/postgresql/data` |
| `postgres:18` and newer | `/var/lib/postgresql/18/docker` | `/var/lib/postgresql`      |

Postgres 18 moved the data directory under a per-major-version subpath so
that one mount point can hold multiple cluster versions side by side
(easing `pg_upgrade`).

HELIOS bind-mounts **whichever target the running image expects** — it does
not standardize on one path:

```
postgres:17 and older →  ${DB_VOLUME_PATH}:/var/lib/postgresql/data
postgres:18 and newer →  ${DB_VOLUME_PATH}:/var/lib/postgresql
```

The export side derives the target from the major version of
`postgresql.image` (`Export::Services::Postgresql#container_data_path`); the
importer accepts either target and records only the host path
(`Import::ConfigurationImporter::VolumeResolver`). Because the image version
is preserved on import, the donor's bind mount round-trips byte-identical and
no `PGDATA` override is ever synthesized.

A single hardcoded target would silently break imports: HELIOS once always
emitted `/var/lib/postgresql` (the pg18 form). Against a `postgres:16` stack
that pointed the container one level too deep, so Postgres found nothing and
initialized a fresh, empty database — see issue #124.
