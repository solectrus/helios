# HELIOS

> [!CAUTION]
> **DO NOT USE — WORK IN PROGRESS**
>
> This project is **not ready for public use**. It is under active development and is **not intended for installation or testing** — not even for evaluation, demos, or experiments.
>
> **Do not install, run, deploy, or promote HELIOS** unless you have been **personally invited and guided by the maintainer ([@ledermann](https://github.com/ledermann))**. There is no support, no documentation for end users, no stability guarantee, and breaking changes happen without notice.
>
> If you stumbled upon this repository: please wait for an official announcement before trying anything.

Web-based bootstrap helper and management interface for [SOLECTRUS](https://solectrus.de). HELIOS eliminates the need to edit `compose.yaml` / `.env` by hand or run `docker compose` commands — install SOLECTRUS once, then configure and operate the full stack through a browser.

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
- ~256 MB RAM for the HELIOS container

## Installation

HELIOS supports two starting points. It auto-detects which one applies on first launch.

### Fresh install

For a new SOLECTRUS setup with no existing `compose.yaml`.

1. Create a directory for the stack and generate a secret in `.env`:

   ```bash
   mkdir -p /opt/solectrus && cd /opt/solectrus
   echo "SECRET_KEY_BASE=$(openssl rand -hex 64)" > .env
   ```

2. Create `compose.yaml` with only the HELIOS service:

   ```yaml
   name: solectrus

   services:
     helios:
       image: ghcr.io/solectrus/helios:develop
       environment:
         - SECRET_KEY_BASE
       volumes:
         - .:/data
         - /var/run/docker.sock:/var/run/docker.sock
       ports:
         - 3999:3000
       restart: unless-stopped
   ```

3. Start the stack:

   ```bash
   docker compose up -d
   ```

HELIOS is now available at `http://<your-host>:3999` and will guide you through the rest of the stack configuration.

### Add to an existing installation

For hosts that already run SOLECTRUS.

1. **Stop the running stack first**, so the next step can safely change the Compose project identity:

   ```bash
   docker compose down
   ```

2. **Edit `compose.yaml`:**

   a. **Set the project name.** HELIOS requires the Compose project to be named `solectrus`. Add this line at the top if it is not already there:

   ```yaml
   name: solectrus
   ```

   Without it, HELIOS refuses to start and shows an error message.

   b. **Add the HELIOS service:**

   ```yaml
   helios:
     image: ghcr.io/solectrus/helios:develop
     environment:
       - ADMIN_PASSWORD
       - SECRET_KEY_BASE
     volumes:
       - .:/data
       - /var/run/docker.sock:/var/run/docker.sock
     ports:
       - 3999:3000
     restart: unless-stopped
   ```

   No changes to `.env` are needed — `ADMIN_PASSWORD` and `SECRET_KEY_BASE` are reused from your existing SOLECTRUS setup.

3. **Start the stack.** All containers are now created under the `solectrus` project and labeled correctly:

   ```bash
   docker compose pull
   docker compose up -d
   ```

HELIOS is now available at `http://<your-host>:3999`.

## First run

On the first visit to `http://<your-host>:3999`:

1. **Existing installations only.** HELIOS shows a consent screen and auto-imports `compose.yaml` and `.env` into its internal configuration, pre-filling sensor mappings from existing env variables.
2. **Configuration wizard.** Walk through the surveys (system, devices, data sources, forecasts, reverse proxy, backup). HELIOS regenerates `compose.yaml` and `.env` after every change. The admin password is a random string generated on first start and stored in `helios/config.yaml` (mirrored to `.env`, since Dashboard and Ingest share it).
3. **Apply changes.** Services are not restarted automatically — the dashboard shows which services are affected and lets you restart them explicitly.

## Documentation

| Document                                          | Description                                |
| ------------------------------------------------- | ------------------------------------------ |
| [Product overview](docs/product.md)               | Scenarios, features, technical constraints |
| [Architecture](docs/architecture/overview.md)     | System diagram, internal storage           |
| [Docker Integration](docs/architecture/docker.md) | Compose, volumes, health checks            |
| [ADRs](docs/adr/)                                 | Architecture Decision Records              |
| [Development Guide](docs/guides/development.md)   | Local setup, testing                       |
| [Open TODOs](docs/todos.md)                       | Work items still ahead                     |

## Development

1. Install dependencies from the [Brewfile](Brewfile):

   ```bash
   brew bundle
   ```

2. Install gems, NPM packages, and create the database:

   ```bash
   bin/setup
   ```

3. Start the app locally:

   ```bash
   bin/dev
   ```

   This starts the app and opens https://helios.localhost in your default browser. On the first run, Caddy will ask for your password to install its local CA certificate.

See the [Development Guide](docs/guides/development.md) for details.

## License

Copyright © 2026 Georg Ledermann. All rights reserved.

HELIOS is currently **unlicensed** — the official Docker image may be pulled and operated for private, non-commercial purposes, but the source code is published for reference only. A formal license will follow. See [`LICENSE.md`](./LICENSE.md) for details.
