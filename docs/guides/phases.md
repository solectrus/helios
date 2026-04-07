# Development Phases

## Status Quo

Phase 0 (Proof of Concept) and Phase 1 (Foundation) are complete. The following is implemented and working:

- Authentication (admin password setup + session management)
- Setup wizard (installation date + timezone)
- Configuration model (YAML-based, stored as `config.yaml` in stack directory)
- Survey-based configuration forms (SurveyJS integration)
- Dashboard with service management UI (start/stop/recreate, batch operations)
- Real-time status updates via Turbo Streams + Action Cable
- Background jobs for async compose operations
- Full `compose.yaml` and `.env` generation (14 services)
- Install script (`install.sh`)
- Theme toggle (light/dark mode)
- ViewComponent-based UI architecture
- compose.yaml/env parsing with comment preservation
- Docker API integration (container status, health) + Compose CLI
- Localization: German + English UI

---

## Phase 2: Configuration ← current

**Goal:** Users can fully configure their SOLECTRUS installation through the web UI — no manual file editing required.

**Two usage scenarios** (see [requirements.md](../spec/requirements.md) FR-3 for details):

| Scenario                 | Description                                               | Collectors                       |
| ------------------------ | --------------------------------------------------------- | -------------------------------- |
| A/B: Fresh install       | Data source selected per device; standalone or smart home | Derived from device data sources |
| C: Existing installation | Auto-import of existing compose.yaml/.env                 | Detected from existing config    |

### 2a: Survey-based configuration

Define all SOLECTRUS usage options through interactive forms (Scenarios A/B + C):

- **Add/remove devices:** Battery, wallbox, car, heat pump, custom consumers
- **Multiple generators:** Support for multiple inverters/roof surfaces
- **Data sources per device:** Direct hardware (SENEC, Shelly), MQTT, ioBroker, Home Assistant — determines which collector services are generated
- **Forecasts:** forecast.solar, Solcast, pvnode
- **System settings:** Machine type, ports, HTTPS/domain, backup

| Status  | Detail                                                           |
| ------- | ---------------------------------------------------------------- |
| ✅ Done | Survey JSON files for all chapters (`config/surveys/`, 15 files) |
| ✅ Done | SurveyJS rendering with theme support and localization           |
| ✅ Done | Configuration model with YAML storage (`config.yaml`)            |
| ✅ Done | Add/remove sensors via UI (create/edit/delete)                   |
| ✅ Done | Conditional dependencies via SurveyJS `visibleIf` expressions    |
| 🔲 TODO | Validation and cross-chapter dependency checks                   |

### 2b: Generate compose.yaml and .env from configuration

Transform stored configuration into a complete, runnable Docker stack (Scenarios A + B):

- Generate `compose.yaml` with all required services based on user's configuration
- Generate `.env` with all environment variables, auto-generated secrets
- Services: PostgreSQL, Redis, InfluxDB, Dashboard, Power-Splitter, Forecast-Collector, Watchtower, Helios, Traefik, hardware collectors (SENEC, Shelly, MQTT), backup services
- Only include services that match the user's configuration

| Status  | Detail                                                                          |
| ------- | ------------------------------------------------------------------------------- |
| ✅ Done | `Export::Builder` orchestrates generation (compose.yaml + .env)                 |
| ✅ Done | `Compose::File` and `Env::File` handle reading/writing                          |
| ✅ Done | 14 service definitions in `Export::Services::*` with `enabled?` predicates      |
| ✅ Done | Conditional service inclusion (e.g. Shelly collector only if Shelly configured) |
| ✅ Done | Secret generation for all required credentials (`ConfigSchema` defaults)        |
| ✅ Done | Service dependency management (`depends_on` with `service_healthy` conditions)  |
| ✅ Done | Auto-regenerate compose.yaml/.env before each compose operation (`ComposeJob`)  |
| ✅ Done | Unmanaged services preserved from existing installations                        |
| ✅ Done | Atomic file writes (`.tmp` + rename) for crash safety                           |

### 2c: Import existing configuration

Enable existing SOLECTRUS users to bring their installation under Helios management (Scenario C):

- On first access, Helios automatically reads existing `compose.yaml` and `.env`
- Reverse-map configuration into chapter data (best-effort)
- Detect which devices/services are configured
- Unknown services and variables are preserved as "unmanaged" — not modified by Helios
- Sensor mappings are read from existing `.env` variables

| Status  | Detail                                                                       |
| ------- | ---------------------------------------------------------------------------- |
| ✅ Done | `Compose::File` can parse existing compose.yaml                              |
| ✅ Done | `Env::File` can parse existing .env with comment preservation                |
| ✅ Done | `StackReader` reads resolved config (`docker compose config`) and raw YAML   |
| ✅ Done | `ConfigurationImporter` extracts configuration from stack                    |
| ✅ Done | Reverse mapping: .env variables → configuration (per-service env access)     |
| ✅ Done | Service detection: SENEC, Shelly, MQTT, Forecast collectors detected         |
| ✅ Done | Unmanaged services/env vars preserved in configuration and restored on write |
| ✅ Done | Auto-import on first access (`before_action` in `ApplicationController`)     |
| 🔲 TODO | Summary/review view after auto-import                                        |
| 🔲 TODO | Web-based editor for unmanaged services and env vars (power-user feature)    |

### 2d: Sensor mapping

Map SOLECTRUS sensors to InfluxDB measurements/fields (all scenarios, but especially important for Scenario C and smart home setups with custom data structures).

**How it works:**

1. **Fresh install with direct collector (Scenario A):** Sensor mappings are pre-filled with service defaults (e.g. `SENEC:inverter_power`). User can view and adjust them after the stack is running. No sensor mapping required before first start.
2. **Existing installation (Scenario C):** Helios reads existing mappings from `.env` and pre-fills the mapping UI.
3. User maps each SOLECTRUS sensor to a measurement/field combination via survey form.
4. Helios writes mappings to `.env`.

**Sensor registry (~40 sensors):**

| Category   | Sensors                                                                                                                                                    |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inverter   | `INVERTER_POWER`, `INVERTER_POWER_1`…`_5`, `GRID_IMPORT_POWER`, `GRID_EXPORT_POWER`, `GRID_EXPORT_LIMIT`, `CASE_TEMP`, `SYSTEM_STATUS`, `SYSTEM_STATUS_OK` |
| Battery    | `BATTERY_SOC`, `BATTERY_CHARGING_POWER`, `BATTERY_DISCHARGING_POWER`                                                                                       |
| Consumers  | `HOUSE_POWER`, `HEATPUMP_POWER`, `CUSTOM_POWER_01`…`_20`                                                                                                   |
| Wallbox/EV | `WALLBOX_POWER`, `WALLBOX_CAR_CONNECTED`, `CAR_BATTERY_SOC`                                                                                                |
| Heat pump  | `HEATPUMP_HEATING_POWER`, `HEATPUMP_TANK_TEMP`, `HEATPUMP_STATUS`, `OUTDOOR_TEMP`                                                                          |
| Forecasts  | `INVERTER_POWER_FORECAST`, `INVERTER_POWER_FORECAST_CLEARSKY`, `OUTDOOR_TEMP_FORECAST`                                                                     |

Each sensor is mapped to a measurement + field combination and stored in `.env`:

```bash
INFLUX_SENSOR_INVERTER_POWER=SENEC:inverter_power
```

| Status  | Detail                                                                              |
| ------- | ----------------------------------------------------------------------------------- |
| ✅ Done | `SensorRegistry` with all sensors, sources, and units                               |
| ✅ Done | `SensorMappings` with defaults for SENEC/Forecast/Shelly/MQTT sources               |
| ✅ Done | Pre-fill defaults for fresh installs; read from `.env` for existing installations   |
| ✅ Done | Sensor mapping not required before first stack start                                |
| ✅ Done | Mapping UI via `sensor.json` survey with dynamic source/measurement/field selection |
| ✅ Done | Store mappings in `.env` (format: `INFLUX_SENSOR_X=measurement:field`)              |
| 🔲 TODO | InfluxDB discovery: auto-query available measurements/fields from running instance  |

---

## Phase 3: Polish & Operations

**Goal:** Production-ready with operational tools and multi-language support.

- System status: Simple health indicator ("Everything OK" / "Problem detected") with alerts (FR-6)
- Log viewer: View, filter, search, and stream container logs (FR-7)
- Update management: Watchtower integration, "Update now" button, changelog display (FR-8)
- Telemetry: Opt-in usage statistics via `update.solectrus.de` (NFR-7)
- Link to running Dashboard from Helios UI
- Error UX: Clear messages with suggested solutions
- Mobile-responsive refinements
