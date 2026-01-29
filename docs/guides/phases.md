# Development Phases

## Phase 0: Proof of Concept

Technical validation before building UI. Rails app without frontend, all testing via `rails console`.

### Goals

Validate that we can:

1. **Read/write compose.yaml** – parse and modify Docker Compose files
2. **Read/write .env** – manage environment variables
3. **Access Docker API** – list containers, read status, stream logs
4. **Execute Compose commands** – `up`, `down`, `pull`, `restart`
5. **Detect stack services** – find containers by Compose labels

### Scope

| In Scope                          | Out of Scope     |
| --------------------------------- | ---------------- |
| Rails app skeleton                | Web UI           |
| Service classes for Docker access | Authentication   |
| Console-based testing             | Database models  |
| `docker-api` gem integration      | Background jobs  |
| `Open3` CLI wrapper               | Configuration UI |
| YAML parsing for compose.yaml     | Install script   |

### Deliverables

```ruby
# Example console session after Phase 0:

# Read compose.yaml
compose = ComposeFile.load('./tmp/stack/compose.yaml')
compose.services.keys
# => ["helios", "postgresql", "redis", "influxdb", "dashboard"]

# Modify and write
compose.add_service('watchtower', image: 'nickfedor/watchtower:latest')
compose.save

# Read/write .env
env = EnvFile.load('./tmp/stack/.env')
env['POSTGRES_PASSWORD']
# => "secretpassword123"
env['NEW_VAR'] = 'value'
env.save

# Docker API access
DockerClient.containers
# => [#<Container name="solectrus-dashboard-1" status="running" health="healthy">, ...]

DockerClient.find('dashboard').logs(tail: 50)
# => "2024-01-15 10:23:45 Rails started..."

DockerClient.find('postgresql').health_status
# => "healthy"

# Compose operations
ComposeRunner.up          # docker compose up -d
ComposeRunner.pull        # docker compose pull
ComposeRunner.restart('dashboard')
```

### Success Criteria

- [ ] Can parse and regenerate compose.yaml without data loss
- [ ] Can read/write .env files preserving comments
- [ ] Can list all containers in the stack
- [ ] Can read container health status
- [ ] Can stream container logs
- [ ] Can execute `docker compose up -d` successfully
- [ ] Works both in development (native) and container environment

---

## Phase 1: MVP

Minimal viable product – first milestone after successful Phase 0.

### User Flow

1. **Installation:** User runs `curl -fsSL solectrus.de/install.sh | sh`
2. **Output:** Script displays URL (e.g., `http://192.168.1.100:3999`)
3. **Browser:** User opens URL in browser
4. **Password:** User sets admin password on first access
5. **Setup:** Helios:
   - Asks for installation date (when PV system was installed, format: `YYYY-MM-DD`)
   - Asks for timezone (e.g., `Europe/Berlin`)
   - Generates `compose.yaml` with required services
   - Creates `.env` with necessary configuration (secrets auto-generated)
   - Starts all services
6. **Done:** User sees "System running" status and can open SOLECTRUS Dashboard (empty, but functional)

### Next Step (User's responsibility)

After MVP setup is complete, the user configures their data source:

- **ioBroker:** Install SOLECTRUS adapter, configure InfluxDB connection
- **Home Assistant:** Install SOLECTRUS integration, configure InfluxDB connection

Once configured, measurement data flows into InfluxDB and appears in the Dashboard.

### MVP Services

Only essential services for a working (but empty) SOLECTRUS:

| Service             | Purpose                    |
| ------------------- | -------------------------- |
| PostgreSQL          | Relational database        |
| Redis               | Background jobs / caching  |
| InfluxDB            | Time-series data storage   |
| SOLECTRUS Dashboard | Main web application       |
| Power-Splitter      | Derived power calculations |

**Not included in MVP:**

- Watchtower (automatic updates)
- Forecast-Collector
- Log viewer
- Update management UI
- Configuration editing UI
- Sensor mapping UI (Phase 2)

### MVP Scope

**Language:** English only (German added in later phase)

| In Scope                   | Out of Scope                  |
| -------------------------- | ----------------------------- |
| Install script (`curl`)    | Existing installation support |
| Password setup             | Multi-language UI             |
| Timezone selection         | Configuration wizard          |
| Auto-generate compose.yaml | System status details         |
| Auto-generate .env         | Troubleshooting tools         |
| Start services             | Any user-facing settings      |
| "System running" indicator |                               |
| Link to Dashboard          |                               |

---

## Phase 2: Sensor Configuration

> **Note:** Sensor mapping UI is not part of MVP. For MVP, default/hardcoded mappings are used.

### Concept

SOLECTRUS defines ~30 sensors with fixed names. Each sensor must be mapped to a specific InfluxDB measurement/field combination.

**Examples of SOLECTRUS sensors:**

- `inverter_power` – Current inverter output (W)
- `battery_soc` – Battery state of charge (%)
- `grid_import_power` – Power imported from grid (W)
- `house_power` – Total house consumption (W)
- `wallbox_power` – EV charger power (W)
- ... (~30 total)

### User Workflow

1. User connects ioBroker/Home Assistant to InfluxDB
2. Data starts flowing into InfluxDB (various measurements/fields)
3. User opens Helios → Sensor Configuration
4. Helios queries InfluxDB for available measurements and fields
5. User maps each SOLECTRUS sensor to an InfluxDB measurement/field
6. Helios saves mapping to configuration

### InfluxDB Discovery

Helios queries InfluxDB to discover available data:

```flux
// Get all measurements
import "influxdata/influxdb/schema"
schema.measurements(bucket: "solectrus")

// Get fields for a measurement
schema.fieldKeys(bucket: "solectrus", measurement: "pv")
```

**Result example:**

```
Measurements: ["pv", "battery", "grid", "house", "wallbox"]
Fields for "pv": ["power", "energy_today", "voltage"]
Fields for "battery": ["soc", "power", "energy"]
```

### UI Concept

```
┌─────────────────────────────────────────────────────────────┐
│  Sensor Configuration                                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Inverter Power                                             │
│  ┌─────────────────────┐  ┌─────────────────────┐           │
│  │ Measurement: [pv ▼] │  │ Field: [power    ▼] │           │
│  └─────────────────────┘  └─────────────────────┘           │
│                                                             │
│  Battery SOC                                                │
│  ┌─────────────────────┐  ┌─────────────────────┐           │
│  │ Measurement: [bat▼] │  │ Field: [soc      ▼] │           │
│  └─────────────────────┘  └─────────────────────┘           │
│                                                             │
│  Grid Import Power                                          │
│  ┌─────────────────────┐  ┌─────────────────────┐           │
│  │ Measurement: [gri▼] │  │ Field: [import   ▼] │           │
│  └─────────────────────┘  └─────────────────────┘           │
│                                                             │
│  ... (more sensors)                                         │
│                                                             │
│  [Save Configuration]                                       │
└─────────────────────────────────────────────────────────────┘
```

### Configuration Storage

Sensor mappings are stored as environment variables in `.env`:

```bash
# Sensor mappings
INVERTER_POWER_MEASUREMENT=pv
INVERTER_POWER_FIELD=power

BATTERY_SOC_MEASUREMENT=battery
BATTERY_SOC_FIELD=soc

GRID_IMPORT_POWER_MEASUREMENT=grid
GRID_IMPORT_POWER_FIELD=import_power
# ...
```

**Principle:** Helios only writes two external files:

- `compose.yaml` – Docker Compose configuration
- `.env` – Environment variables

All internal state (setup status, managed services, etc.) is stored in SQLite.

### Sensor Registry

Complete list of SOLECTRUS sensors (from [docs.solectrus.de](https://docs.solectrus.de/referenz/dashboard/sensor-konfiguration/)):

**Inverter**

| Sensor                      | Description                 | Unit    |
| --------------------------- | --------------------------- | ------- |
| `INVERTER_POWER`            | Total PV generation         | W       |
| `INVERTER_POWER_1` ... `_5` | Up to 5 separate generators | W       |
| `GRID_IMPORT_POWER`         | Grid import                 | W       |
| `GRID_EXPORT_POWER`         | Grid export                 | W       |
| `GRID_EXPORT_LIMIT`         | Feed-in limit               | %       |
| `CASE_TEMP`                 | Inverter case temperature   | °C      |
| `SYSTEM_STATUS`             | System status / errors      | Text    |
| `SYSTEM_STATUS_OK`          | Status indicator            | Boolean |

**Battery**

| Sensor                      | Description             | Unit |
| --------------------------- | ----------------------- | ---- |
| `BATTERY_SOC`               | Battery state of charge | %    |
| `BATTERY_CHARGING_POWER`    | Charging power          | W    |
| `BATTERY_DISCHARGING_POWER` | Discharging power       | W    |

**Consumers**

| Sensor                      | Description               | Unit |
| --------------------------- | ------------------------- | ---- |
| `HOUSE_POWER`               | House consumption         | W    |
| `HEATPUMP_POWER`            | Heat pump power           | W    |
| `CUSTOM_POWER_01` ... `_20` | Custom sensors (up to 20) | W    |

**Wallbox & EV**

| Sensor                  | Description                | Unit    |
| ----------------------- | -------------------------- | ------- |
| `WALLBOX_POWER`         | Wallbox charging power     | W       |
| `WALLBOX_CAR_CONNECTED` | Car connected status       | Boolean |
| `CAR_BATTERY_SOC`       | EV battery state of charge | %       |

**Heat Pump**

| Sensor                   | Description                | Unit |
| ------------------------ | -------------------------- | ---- |
| `HEATPUMP_HEATING_POWER` | Generated heat power       | W    |
| `HEATPUMP_TANK_TEMP`     | Hot water tank temperature | °C   |
| `HEATPUMP_STATUS`        | Operating status           | Text |
| `OUTDOOR_TEMP`           | Outdoor temperature        | °C   |

**Forecasts**

| Sensor                             | Description              | Unit |
| ---------------------------------- | ------------------------ | ---- |
| `INVERTER_POWER_FORECAST`          | Forecasted PV generation | W    |
| `INVERTER_POWER_FORECAST_CLEARSKY` | Max possible generation  | W    |
| `OUTDOOR_TEMP_FORECAST`            | Forecasted outdoor temp  | °C   |

**Total: ~40 sensors** (including custom sensors)

### For Existing Users

When Helios is added to an existing installation:

1. Helios reads existing `.env` file
2. Parses existing sensor mappings
3. Displays current configuration in UI
4. User can modify mappings if needed
