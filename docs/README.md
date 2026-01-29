# Helios

Web-based bootstrap helper and management interface for SOLECTRUS.

## Problem

Installing and configuring SOLECTRUS currently requires:

- Linux command line knowledge
- Understanding of Docker and Docker Compose
- Manual editing of `compose.yaml` and `.env` files

This technical barrier prevents many users from adopting SOLECTRUS.

## Solution

Helios provides a web-based interface that handles all aspects of SOLECTRUS installation, configuration, and operation. It eliminates the need for users to manually edit configuration files or understand Docker internals.

## Target Users

1. **New users:** Fresh SOLECTRUS installation via Helios
2. **Existing users:** Already have SOLECTRUS running, add Helios for easier management

## Data Integration

Measurement data flows into SOLECTRUS via:

- **ioBroker** (ioBroker adapter pushes to InfluxDB)
- **Home Assistant** (Home Assistant integration pushes to InfluxDB)

This means:

- No hardware-specific collectors required (SENEC, Shelly, etc.)
- Minimal environment configuration needed
- Simpler setup wizard for new users

**Note:** Power-Splitter and Forecast-Collector are SOLECTRUS-specific services that cannot be replaced by ioBroker/Home Assistant. These are managed by Helios.

## Documentation

| Document                                             | Description                                     |
| ---------------------------------------------------- | ----------------------------------------------- |
| [spec/requirements.md](spec/requirements.md)         | Functional and non-functional requirements      |
| [architecture/overview.md](architecture/overview.md) | Tech stack, components, storage                 |
| [architecture/docker.md](architecture/docker.md)     | Docker integration, compose.yaml, health checks |
| [adr/](adr/README.md)                                | Architecture Decision Records                   |
| [guides/development.md](guides/development.md)       | Local setup, testing                            |
| [guides/phases.md](guides/phases.md)                 | Phase 0, MVP, roadmap                           |
