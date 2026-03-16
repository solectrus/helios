# Requirements

## Functional Requirements

### FR-1: One-Command Installation (New Users)

- **Prerequisite:** Docker and Docker Compose must be installed
- Installation via single shell command: `curl -fsSL solectrus.de/install.sh | sh`
- The install script shall:
  - Check that Docker and Docker Compose are available
  - Detect the architecture (AMD64/ARM64)
  - Create a `compose.yaml` with only Helios
  - Start the Docker stack
  - Display the URL to access Helios

### FR-2: Manual Installation (Existing Users)

- Existing SOLECTRUS users can **optionally** add Helios to their setup
- User manually adds Helios service to their existing `compose.yaml`
- Documentation provides copy-paste snippet for the service definition
- Helios is not required – existing setups continue to work without it

### FR-3: Initial Setup

- On first access, prompt user to set an admin password
- Helios detects the environment and guides the user through one of three scenarios:

**Scenario A/B: Fresh install**

- No other services running yet (only Helios service in `compose.yaml`)
- User defines devices through configuration wizard (inverter, battery, wallbox, heat pump, etc.)
- For each device, user selects the data source (e.g. SENEC direct, Shelly, MQTT, ioBroker, Home Assistant)
- Helios generates collector services only for devices with direct hardware data sources:
  - SENEC collector (V3 local API or V4 cloud API)
  - Shelly collector (one or more, local API)
  - MQTT collector (generic, requires sensor-to-topic mapping)
- If all data flows via an external smart home system (ioBroker/HA), no collector services are generated
- Forecast-Collector and Power-Splitter are always included
- Sensor mappings are pre-filled with service defaults; user can adjust after the stack is running
- Helios generates `compose.yaml` and `.env`, starts the stack

**Scenario C: Existing installation**

- SOLECTRUS services already running with existing `compose.yaml` and `.env`
- On first access, Helios automatically reads and imports the existing files
- Configuration is reverse-mapped into internal chapter data (best-effort)
- Sensor mappings are read from existing `.env` variables and pre-filled in the mapping UI
- Unknown services and variables are preserved as "unmanaged" — not modified by Helios
- User sees the detected configuration and can correct or complete it

### FR-4: Service Management

- Helios manages required backend services transparently (user doesn't see "Docker" or "containers")
- Services are added/configured automatically based on user's setup choices
- Managed services (invisible to user):
  - Watchtower (automatic updates)
  - InfluxDB (time-series database)
  - PostgreSQL (relational database)
  - Redis (caching/background jobs)
  - SOLECTRUS Dashboard (main application)
  - Power-Splitter (calculates derived power values)
  - Forecast-Collector (fetches solar forecast data)
  - SENEC collector (if SENEC device configured)
  - Shelly collector (if Shelly device configured, multiple instances possible)
  - MQTT collector (if MQTT data source configured)
- **Custom services:** User-added services in `compose.yaml` are preserved and not modified by Helios

### FR-5: Configuration Management

- Web-based editing of environment variables (`.env`)
- Guided configuration forms with validation
- No direct file editing required by users
- `compose.yaml` and `.env` are regenerated automatically after each configuration change
- Services are **not** restarted automatically — user triggers restart explicitly via service management

### FR-6: System Status

- Simple health indicator: "Everything OK" or "Problem detected"
- Show alerts if something needs attention
- Details available for troubleshooting (but not prominently displayed)

### FR-7: Log Viewer

- View logs for any container
- Filter by time range and severity
- Search within logs
- Real-time log streaming (tail -f equivalent)

### FR-8: Update Management

- **Automatic updates:** Watchtower container monitors and updates all images (including Helios itself)
- **Manual trigger:** Optional "Update now" button to trigger immediate update check
- **Update detection:** Query Docker registry to check if newer image exists for `latest` tag
- Display changelog / release notes (fetched from GitHub) before updating

---

## Non-Functional Requirements

### NFR-1: Platform Support

- **Architectures:** AMD64, ARM64
- **Target systems:**
  - Raspberry Pi (3, 4, 5)
  - NAS devices (Synology, QNAP with Docker support)
  - Virtual private servers (VPS)
  - Any Linux system with Docker support

### NFR-2: Technology Stack

- **Framework:** Ruby on Rails 8.1+
- **Frontend:** Hotwire (Turbo + Stimulus)
- **CSS:** TailwindCSS 4 + DaisyUI
- **Asset Bundler:** Vite (via vite_ruby)
- **Database:** SQLite (for Helios internal data)
- **Testing:** RSpec
- **Containerization:** Docker, managed via Docker Compose

### NFR-3: Network & Access

- Web interface accessible via LAN only
- Default port: 3999
- URL example: `http://<host-ip>:3999`
- No external/internet access required for basic operation

### NFR-4: Security

- Single admin user with password (set on first run)
- Session persists indefinitely (no auto-logout)
- Docker socket access (`/var/run/docker.sock`) required
- All configuration files stored with appropriate permissions
- No sensitive data exposed in logs

### NFR-5: Resource Efficiency

- Minimal footprint (Helios itself should be lightweight)
- Suitable for resource-constrained devices (Raspberry Pi)
- Target: < 256 MB RAM for Helios container

### NFR-6: User Experience

- Intuitive UI requiring no Docker/Linux knowledge
- Responsive design (usable on mobile devices)
- Clear error messages with suggested solutions
- Progress indicators for long-running operations
- **Localization:** English and German language support

### NFR-7: Telemetry

- Optional (opt-in) telemetry via `update.solectrus.de`
- Used for update checks and anonymous usage statistics
- User must consent during initial setup

---

## Out of Scope (v1)

- Backup/restore for user data (InfluxDB, PostgreSQL)
- Remote access via secure tunnel
- Multi-site management
- API for external integrations
- Plugin system for additional adapters
