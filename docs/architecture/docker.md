# Docker Integration

## Access Method: Docker Socket

Helios accesses Docker via the Unix socket `/var/run/docker.sock`.

**Why Docker Socket?**

- Industry standard (used by Portainer, Watchtower, etc.)
- Full Docker API access
- No additional configuration required
- Works with Docker Compose operations

**Required permissions:**

- Socket must be mounted into Helios container
- Helios runs with access to docker group (or root)

### File Access

Helios needs read/write access to:

- `compose.yaml` – to add/modify services
- `.env` – to manage environment variables

**Solution:** Mount the SOLECTRUS directory as a volume.

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
  - /opt/solectrus:/app/solectrus # or wherever SOLECTRUS lives
```

---

## Docker Compose Operations

Helios performs these operations via Docker API / CLI:

| Operation               | How                                     |
| ----------------------- | --------------------------------------- |
| Read running containers | Docker API: `GET /containers/json`      |
| Start stack             | `docker compose up -d`                  |
| Stop stack              | `docker compose down`                   |
| Restart service         | `docker compose restart <service>`      |
| Pull new images         | `docker compose pull`                   |
| View logs               | Docker API: `GET /containers/{id}/logs` |

### Implementation

Helios uses a hybrid approach:

**1. `docker-api` Gem** – for direct Docker API access

```ruby
# Gemfile
gem 'docker-api'

# Usage
Docker.url = 'unix:///var/run/docker.sock'
containers = Docker::Container.all
container.logs(stdout: true, tail: 100)
container.json['State']['Health']['Status']
```

Used for:

- Reading container status and health
- Streaming logs
- Inspecting container details

**2. CLI via `Open3`** – for Docker Compose operations

```ruby
require 'open3'

def compose_up
  stdout, stderr, status = Open3.capture3(
    'docker', 'compose', 'up', '-d',
    chdir: stack_path
  )
  raise ComposeError, stderr unless status.success?
end
```

Used for:

- `docker compose up -d` – start stack
- `docker compose down` – stop stack
- `docker compose pull` – pull new images
- `docker compose restart <service>` – restart service

**Rationale:** The `docker-api` gem provides clean Ruby access to container info and logs, but cannot execute `docker compose` commands. Compose operations require CLI because they involve YAML parsing, service dependencies, and network setup that only the Compose CLI handles.

---

## Generated Files

### compose.yaml (MVP)

```yaml
name: solectrus

services:
  helios:
    image: ghcr.io/solectrus/helios:latest
    ports:
      - '3999:3000'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - .:/app/solectrus
      - ./helios:/app/data
    restart: unless-stopped

  postgresql:
    image: postgres:18-alpine
    environment:
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=solectrus
    volumes:
      - ./postgresql:/var/lib/postgresql/data
    restart: unless-stopped

  redis:
    image: redis:8-alpine
    volumes:
      - ./redis:/data
    restart: unless-stopped

  influxdb:
    image: influxdb:2-alpine
    ports:
      - '8086:8086'
    environment:
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=admin
      - DOCKER_INFLUXDB_INIT_PASSWORD=${INFLUX_PASSWORD}
      - DOCKER_INFLUXDB_INIT_ORG=${INFLUX_ORG}
      - DOCKER_INFLUXDB_INIT_BUCKET=${INFLUX_BUCKET}
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=${INFLUX_TOKEN}
    volumes:
      - ./influxdb:/var/lib/influxdb2
    restart: unless-stopped

  dashboard:
    image: ghcr.io/solectrus/solectrus:latest
    ports:
      - '3000:3000'
    environment:
      - DATABASE_URL=postgres://postgres:${POSTGRES_PASSWORD}@postgresql/solectrus
      - REDIS_URL=redis://redis:6379
      - INFLUX_HOST=influxdb
      - INFLUX_TOKEN=${INFLUX_TOKEN}
      - INFLUX_ORG=${INFLUX_ORG}
      - INFLUX_BUCKET=${INFLUX_BUCKET}
      - SECRET_KEY_BASE=${SECRET_KEY_BASE}
      - APP_HOST=${APP_HOST:-localhost}
      - INSTALLATION_DATE=${INSTALLATION_DATE}
    depends_on:
      - postgresql
      - redis
      - influxdb
    restart: unless-stopped

  power-splitter:
    image: ghcr.io/solectrus/power-splitter:latest
    environment:
      - TZ=${TZ}
      - INSTALLATION_DATE=${INSTALLATION_DATE}
      - INFLUX_HOST=influxdb
      - INFLUX_TOKEN=${INFLUX_TOKEN}
      - INFLUX_ORG=${INFLUX_ORG}
      - INFLUX_BUCKET=${INFLUX_BUCKET}
      - INFLUX_SENSOR_GRID_IMPORT_POWER=${INFLUX_SENSOR_GRID_IMPORT_POWER}
      - INFLUX_SENSOR_HOUSE_POWER=${INFLUX_SENSOR_HOUSE_POWER}
      - INFLUX_SENSOR_WALLBOX_POWER=${INFLUX_SENSOR_WALLBOX_POWER:-}
      - INFLUX_SENSOR_HEATPUMP_POWER=${INFLUX_SENSOR_HEATPUMP_POWER:-}
      - INFLUX_SENSOR_BATTERY_CHARGING_POWER=${INFLUX_SENSOR_BATTERY_CHARGING_POWER:-}
      - INFLUX_EXCLUDE_FROM_HOUSE_POWER=${INFLUX_EXCLUDE_FROM_HOUSE_POWER:-}
      - REDIS_URL=redis://redis:6379
      - DB_HOST=postgresql
      - DB_USER=postgres
      - DB_PASSWORD=${POSTGRES_PASSWORD}
    depends_on:
      - influxdb
      - redis
      - postgresql
    restart: unless-stopped
```

### .env (MVP)

```bash
# Generated by Helios
# Do not edit manually

# General
TZ=<user-provided>
INSTALLATION_DATE=<user-provided>

# PostgreSQL
POSTGRES_PASSWORD=<generated>

# InfluxDB
INFLUX_PASSWORD=<generated>
INFLUX_ORG=solectrus
INFLUX_BUCKET=solectrus
INFLUX_TOKEN=<generated>

# Dashboard
SECRET_KEY_BASE=<generated>

# Sensor mappings (configured in Phase 2, defaults for MVP)
INFLUX_SENSOR_GRID_IMPORT_POWER=
INFLUX_SENSOR_HOUSE_POWER=
INFLUX_SENSOR_WALLBOX_POWER=
INFLUX_SENSOR_HEATPUMP_POWER=
INFLUX_SENSOR_BATTERY_CHARGING_POWER=
INFLUX_EXCLUDE_FROM_HOUSE_POWER=
```

**Notes:**

- All secrets are auto-generated during setup (`SecureRandom.hex(64)` or similar)
- `INSTALLATION_DATE` is collected from the user during initial setup (format: `YYYY-MM-DD`)
- `TZ` is collected from the user during initial setup (e.g., `Europe/Berlin`)
- Sensor mappings are empty in MVP; configured via UI in Phase 2

---

## Installation Scenario Detection

Helios detects whether it's a fresh installation (Scenario A) or an existing installation (Scenario B) at startup.

**Detection method:** Check if `compose.yaml` contains services other than Helios.

```ruby
compose = ComposeFile.load('compose.yaml')
services = compose.services.keys

if services == ['helios']
  # Scenario A: Fresh installation
  # Guide user through setup wizard
else
  # Scenario B: Existing installation
  # Import and display existing configuration
end
```

**Scenario A (Fresh):** Only Helios service exists → show setup wizard.

**Scenario B (Existing):** Other services present → import configuration, show overview.

---

## Error Handling

### Docker Not Reachable

If Docker socket is not accessible (not mounted, daemon stopped):

- Helios shows a dedicated error page
- Message: "Cannot connect to Docker"
- Troubleshooting hints provided (check socket mount, Docker daemon status)
- No other functionality available until resolved

### Missing or Corrupt compose.yaml

If `compose.yaml` is missing or invalid after initial setup:

- Helios can regenerate the file from its internal service registry (SQLite)
- User is prompted: "Configuration file missing. Regenerate from saved state?"
- Regeneration restores all Helios-managed services
- User-added services cannot be recovered (warning shown)

---

## Stack Detection

Helios detects other services in the same Docker Compose stack via labels.

Docker Compose automatically sets these labels on all containers:

- `com.docker.compose.project` – project name (usually directory name)
- `com.docker.compose.service` – service name from compose.yaml

**Detection method:**

```bash
# Get project name from own container
PROJECT=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' $(hostname))

# List all services in same project
docker ps --filter "label=com.docker.compose.project=$PROJECT" --format "{{.Names}}"
```

This works reliably because SOLECTRUS always uses Docker Compose (never `docker run`).

---

## Image Versioning Strategy

| Service             | Image Tag                                     | Rationale                     |
| ------------------- | --------------------------------------------- | ----------------------------- |
| SOLECTRUS Dashboard | `ghcr.io/solectrus/solectrus:latest`          | Own service, always latest    |
| Helios              | `ghcr.io/solectrus/helios:latest`             | Own service, always latest    |
| Power-Splitter      | `ghcr.io/solectrus/power-splitter:latest`     | Own service, always latest    |
| Forecast-Collector  | `ghcr.io/solectrus/forecast-collector:latest` | Own service, always latest    |
| PostgreSQL          | `postgres:18-alpine`                          | Major version pinned          |
| Redis               | `redis:8-alpine`                              | Major version pinned          |
| InfluxDB            | `influxdb:2-alpine`                           | Major version pinned          |
| Watchtower          | `nickfedor/watchtower:latest`                 | Fork with additional features |

**Rationale:**

- Own services use `latest` – Watchtower handles updates automatically
- Third-party services pin major version – prevents breaking changes, allows minor/patch updates

---

## Compose File Conflict Handling

When Helios needs to modify `compose.yaml` (e.g., adding a service), it may encounter user modifications.

**Strategy: Detect and warn**

1. Helios tracks which services it manages (stored in SQLite)
2. Before modifying, compare current file with expected state
3. If differences detected in managed services → show warning to user
4. User decides: apply changes, skip, or review diff

**What Helios tracks:**

- Services it created (e.g., `dashboard`, `postgresql`, `influxdb`)
- Expected configuration for each service

**What Helios ignores:**

- Services it doesn't know (user-added, e.g., `traefik`)
- These are preserved as-is

**Example conflict scenarios:**

| Scenario                         | Helios behavior                                          |
| -------------------------------- | -------------------------------------------------------- |
| User changed port of `dashboard` | Warning: "Port was modified. Keep your change or reset?" |
| User added `traefik` service     | No warning, service is preserved                         |
| User removed `redis`             | Warning: "Required service missing. Re-add?"             |

---

## Health Checks

Health checks are defined natively in Docker Compose. Helios reads the health status from Docker API.

**Approach:**

- Each service defines its own `healthcheck` in compose.yaml
- Docker reports status: `healthy`, `unhealthy`, `starting`
- Helios queries: `docker inspect --format '{{.State.Health.Status}}' <container>`

**Example health checks for compose.yaml:**

```yaml
postgresql:
  healthcheck:
    test: ['CMD-SHELL', 'pg_isready -U postgres']
    interval: 10s
    timeout: 5s
    retries: 3

redis:
  healthcheck:
    test: ['CMD', 'redis-cli', 'ping']
    interval: 10s
    timeout: 5s
    retries: 3

influxdb:
  healthcheck:
    test: ['CMD', 'curl', '-f', 'http://localhost:8086/health']
    interval: 10s
    timeout: 5s
    retries: 3

dashboard:
  healthcheck:
    test: ['CMD', 'curl', '-f', 'http://localhost:3000/up']
    interval: 10s
    timeout: 5s
    retries: 3
```

**Helios behavior:**

- Displays overall status: "All services healthy" or "Problem detected"
- On problem: Shows which service is unhealthy
- No active polling by Helios – relies on Docker's health check mechanism
