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

## Usage Scenarios

### Scenario A: Fresh install, standalone

New installation without smart home system. Helios guides through device configuration and generates collector services (SENEC, Shelly, MQTT) to read data directly from hardware. Forecast-Collector and Power-Splitter are always included.

### Scenario B: Fresh install, smart home

New installation with ioBroker or Home Assistant. The smart home system pushes data to InfluxDB — no collector services needed. Helios generates only infrastructure services plus Forecast-Collector and Power-Splitter.

### Scenario C: Existing installation

Existing SOLECTRUS installation with `compose.yaml` and `.env`. Helios reads the files, reverse-maps the configuration, and becomes the management layer. Best-effort detection — user verifies and corrects.

**Note:** Scenarios A and B can coexist (e.g. SENEC collector for inverter + ioBroker for other sensors).

## Documentation

| Document                                             | Description                                     |
| ---------------------------------------------------- | ----------------------------------------------- |
| [spec/requirements.md](spec/requirements.md)         | Functional and non-functional requirements      |
| [architecture/overview.md](architecture/overview.md) | Tech stack, components, storage                 |
| [architecture/docker.md](architecture/docker.md)     | Docker integration, compose.yaml, health checks |
| [adr/](adr/README.md)                                | Architecture Decision Records                   |
| [guides/development.md](guides/development.md)       | Local setup, testing                            |
| [guides/phases.md](guides/phases.md)                 | Development phases and current scope            |
