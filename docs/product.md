# What HELIOS Does

HELIOS is a web-based management tool for [SOLECTRUS](https://solectrus.de). It removes the need to edit `compose.yaml` / `.env` by hand or type `docker compose` commands — administrators install, configure, and operate their SOLECTRUS stack through the browser.

---

## Installation Scenarios

HELIOS covers three situations out of the box. They are detected automatically at startup from the contents of `compose.yaml`.

### A — Fresh install, standalone

No other services running yet. HELIOS guides the user through device configuration (inverter, battery, wallbox, heat pump, custom consumers) and generates collector services to read data directly from hardware (SENEC, Shelly, MQTT). `Forecast-Collector` is always included; `Power-Splitter` is added once grid import, house power and at least one further consumer are mapped.

### B — Fresh install, smart home

Data is pushed into InfluxDB by an external system (ioBroker, Home Assistant). No collectors are generated — HELIOS only provisions infrastructure services plus `Forecast-Collector` and `Power-Splitter`.

### C — Existing installation

`compose.yaml` and `.env` already exist. On first access, HELIOS reads both files, reverse-maps the configuration into its internal singletons (best-effort), pre-fills sensor mappings from existing env variables, and preserves any services / variables it does not understand as "unmanaged". The user reviews and corrects.

Scenarios A and B can coexist (e.g. SENEC collector for the inverter + ioBroker for everything else).

---

## Feature Overview

### Installation

- **Fresh install** (new users): create a minimal `compose.yaml` containing only the `helios` service and start it. HELIOS then guides the user through the full stack configuration.
- **Add to existing installation** (existing users): a short snippet adds `helios` to the existing `compose.yaml`. HELIOS is opt-in — existing setups keep working without it.

### First-Run Setup

- Admin password is set on first access (stored as a random plaintext string in `config.yaml` and mirrored to `.env` as `ADMIN_PASSWORD`, because the Dashboard service needs the same value).
- HELIOS auto-detects the scenario. For scenario C it runs the auto-import before the UI appears for the first time.

### Configuration Management

- Survey-based forms (SurveyJS) cover every documented SOLECTRUS environment variable: devices, data sources, forecasts, HTTPS / reverse proxy, backup, system settings.
- `compose.yaml` and `.env` are regenerated automatically after every change.
- Services are **not** restarted automatically — the user triggers restarts explicitly. The UI shows which services are affected by pending config changes.

### Sensor Mapping

- Registry of ~50 SOLECTRUS sensors (inverter / grid / battery / wallbox / car / heat pump / system / forecasts / 20 custom consumer slots) — see [`SensorRegistry::SENSORS`](../app/models/sensor_registry.rb).
- Each sensor is mapped to a `measurement:field` combination and written to `.env` as `INFLUX_SENSOR_*`.
- Fresh installs are pre-filled with service defaults; existing installs are pre-filled from the current `.env`.
- Live readings are shown in the mapping UI, queried from the running InfluxDB.

### Service Management

- Dashboard lists all services with live status, version, and health.
- Per-service actions: start, stop, restart, recreate; plus batch operations across the stack.
- Orphaned-service detection and cleanup.
- Live log viewer with ANSI colors and tail loading.
- Real-time status updates via Turbo Streams + Action Cable — no polling, driven by the Docker events API.

### Updates

- `Watchtower` is part of the generated stack and updates all images automatically, including HELIOS itself.
- The update check runs either on an interval (`WATCHTOWER_POLL_INTERVAL`) or daily at a fixed local time (`WATCHTOWER_SCHEDULE`, a 6-field cron). The software survey picks one; Watchtower rejects both at once. See `WatchtowerSchedule`.
- Image versioning strategy: own services track `latest` (Watchtower-managed), third-party services pin a major version. See [architecture/docker.md](architecture/docker.md#image-versioning-strategy).

### Backup

- HELIOS' built-in backup runner writes one tar archive per backup, bundling the PostgreSQL dump, the InfluxDB export and the active `config.yaml`. Backups are created on demand from the UI or daily at a configured time (see `BackupScheduler`); the five newest are kept, older ones are pruned automatically.
- Three destinations are available: the local backups directory under the HELIOS data path, an external host mount (e.g. an NFS share on a NAS) or an S3-compatible object store (AWS S3, MinIO, Backblaze B2, Wasabi …).
- Restore is initiated from the UI; it runs in a detached container, stops the stack, wipes the database directories, imports the dumps and restarts everything.

### Support Bundle

- On-demand ZIP download for troubleshooting. Bundles `compose.yaml`, `.env`, `config.yaml` (plus their `.bak` variants), a `system-info.txt` snapshot (HELIOS version, Docker engine, OS / CPU / memory / disk, container table) and the last 200 log lines per container under `logs/`.
- Secrets (passwords, tokens, API keys, geolocation) are replaced with deterministic placeholders (e.g. `dummy_postgres_password`) so the archive is safe to post in a public forum and a restored copy still starts locally.

---

## Technical Constraints

| Area               | Constraint                                                                                                                                                 |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Architectures      | AMD64, ARM64                                                                                                                                               |
| Target hosts       | Raspberry Pi (3/4/5), NAS (Synology DSM 7.2+ with Container Manager, QNAP with Docker), VPS, any Linux with Docker Engine ≥ 24.0 and the Compose v2 plugin |
| Tech stack         | Rails 8.1+, Hotwire (Turbo + Stimulus, TypeScript), Tailwind v4 + daisyUI, Vite, SQLite, RSpec. See [ADR-0007](adr/0007-technology-stack.md).              |
| Network            | LAN-only by default, port 3999 (`http://<host-ip>:3999`). No outbound internet required.                                                                   |
| Security           | Single admin with random password (stored plaintext in `config.yaml`, mirrored to `.env`). Docker socket mount required. Session persists indefinitely.    |
| Resource footprint | Target < 256 MB RAM for the HELIOS container (suitable for Raspberry Pi)                                                                                   |
| Localization       | German + English UI                                                                                                                                        |
| Telemetry          | Planned: opt-in update checks + anonymous usage stats via `update.solectrus.de`. Not yet implemented.                                                      |
