# HELIOS

Web-based control panel for [SOLECTRUS](https://solectrus.de). HELIOS installs the SOLECTRUS stack on your Docker host and lets you configure and operate it through a browser, replacing manual edits to `compose.yaml` / `.env` and `docker compose` commands.

> [!WARNING]
> **Pre-1.0 — early release, test environments only**
>
> HELIOS is usable but unfinished. Expect rough edges, missing end-user documentation, and breaking changes between 0.x releases without migration paths. There is no stability guarantee yet.
>
> **Do not use in production.** Run HELIOS only against test or evaluation stacks where data loss or downtime is acceptable. If you want to try it, you should be comfortable inspecting `compose.yaml` / `.env` yourself in case something goes wrong. For production stacks, wait for 1.0.

## Screenshots

|                                  Configuration                                  |                               Services                                |
| :-----------------------------------------------------------------------------: | :-------------------------------------------------------------------: |
| <img src="screenshot-configuration.jpg" alt="HELIOS configuration" width="450"> | <img src="screenshot-services.jpg" alt="HELIOS services" width="450"> |

## Features

- **Service dashboard** — live status, versions, health for every container; start / stop / restart / recreate per service or in batch.
- **Survey-based configuration** — guided forms cover every documented SOLECTRUS environment variable (devices, data sources, forecasts, reverse proxy, backup).
- **Sensor mapping** — registry of ~40 SOLECTRUS sensors with live readings from InfluxDB.
- **Live logs** — tail and search container logs with ANSI colors directly in the UI.
- **Auto-import** — detects existing SOLECTRUS installations, reverse-maps the configuration, and preserves anything it does not understand.
- **Auto-updates** — Watchtower keeps all images (including HELIOS itself) current.
- **Real-time UI** — status updates via Turbo Streams + Action Cable, driven by the Docker events API. No polling.
- **Support bundle** — download a ZIP of the current configuration, container logs, and host snapshot for troubleshooting; secrets are redacted with placeholder values so the bundle can be shared publicly.
- **Localized** — German and English.

## Requirements

- Docker and Docker Compose (v2)
- Architecture: AMD64 or ARM64 (Raspberry Pi 3/4/5, NAS, VPS, any Linux host)
- Port 3999 available on the host
- ~384 MB RAM for the HELIOS container

## Installation

HELIOS runs as one service inside your SOLECTRUS Docker Compose stack. The bootstrap script handles everything — whether you're setting up SOLECTRUS for the first time or adding HELIOS to a host that already runs it.

Pick the case that matches your setup:

**a) New install** — pick a permanent location on a disk with enough free space (the databases will live here long-term, e.g. `/opt/solectrus` or `~/solectrus`), create the directory and `cd` into it:

```bash
mkdir -p /opt/solectrus && cd /opt/solectrus
```

**b) Existing SOLECTRUS stack** — `cd` into the directory that holds your current `compose.yaml` and `.env`:

```bash
cd /path/to/your/solectrus
```

Then run the bootstrap script:

```bash
curl -fsSL https://raw.githubusercontent.com/solectrus/helios/develop/bootstrap/install.sh | bash
```

When it finishes, HELIOS is available at `http://<your-host>:3999`.

> Prefer not to pipe `curl | bash`? Download `bootstrap/install.sh`, review it, and run it locally.

## First run

On the first visit to `http://<your-host>:3999`:

1. **Login.** Use the `ADMIN_PASSWORD` from `.env` (printed by the bootstrap script on a fresh install, or your existing one when adding HELIOS to a running stack).
2. **Existing installations only.** HELIOS shows a consent screen and auto-imports `compose.yaml` and `.env` into its internal configuration, pre-filling sensor mappings from existing env variables.
3. **Configuration wizard.** Walk through the surveys (system, devices, data sources, forecasts, reverse proxy, backup). HELIOS regenerates `compose.yaml` and `.env` after every change.
4. **Apply changes.** Services are not restarted automatically — the dashboard shows which services are affected and lets you restart them explicitly.

## Documentation

| Document                                          | Description                                |
| ------------------------------------------------- | ------------------------------------------ |
| [Product overview](docs/product.md)               | Scenarios, features, technical constraints |
| [Architecture](docs/architecture/overview.md)     | System diagram, internal storage           |
| [Docker Integration](docs/architecture/docker.md) | Compose, volumes, health checks            |
| [ADRs](docs/adr/)                                 | Architecture Decision Records              |
| [Development Guide](docs/guides/development.md)   | Local setup, testing                       |
| [Open TODOs](docs/todos.md)                       | Work items still ahead                     |

## License

Copyright © 2026 Georg Ledermann. All rights reserved.

HELIOS is currently **unlicensed** — the official Docker image may be pulled and operated for private, non-commercial purposes, but the source code is published for reference only. A formal license will follow. See [`LICENSE.md`](./LICENSE.md) for details.
