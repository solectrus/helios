# Development Phases

## Status Quo

Phase 0 (Proof of Concept) and Phase 1 (Foundation) are complete. The following is implemented and working:

- Authentication (admin password setup + session management)
- Setup wizard (installation date + timezone)
- Configuration model (chapters-based, stored as JSON in SQLite)
- Survey-based configuration forms (SurveyJS integration)
- Dashboard with service management UI (start/stop/recreate, batch operations)
- Real-time status updates via Turbo Streams + Action Cable
- Background jobs for async compose operations
- Basic `compose.yaml` and `.env` generation (MVP services: PostgreSQL, Redis, InfluxDB, Dashboard)
- Install script (`install.sh`)
- Theme toggle (light/dark mode)
- ViewComponent-based UI architecture
- compose.yaml/env parsing with comment preservation
- Docker API integration (container status, health) + Compose CLI

---

## Phase 2: Configuration ← current

**Goal:** Users can fully configure their SOLECTRUS installation through the web UI — no manual file editing required.

**Three usage scenarios** (see [requirements.md](../spec/requirements.md) FR-3 for details):

| Scenario | Description | Collectors |
| -------- | ----------- | ---------- |
| A: Fresh install, standalone | No smart home system, direct hardware access | SENEC, Shelly, MQTT + Forecast + Power-Splitter |
| B: Fresh install, smart home | External data source (ioBroker/HA) | Forecast + Power-Splitter only |
| C: Existing installation | Import existing compose.yaml/.env | Detect from existing config |

### 2a: Survey-based configuration

Define all SOLECTRUS usage options through interactive forms (Scenarios A + B):

- **Add/remove devices:** Battery, wallbox, car, heat pump, custom consumers
- **Multiple generators:** Support for multiple inverters/roof surfaces
- **Data sources:** Direct hardware (SENEC, Shelly), MQTT, ioBroker, Home Assistant
- **Forecasts:** forecast.solar, Solcast
- **System settings:** Machine type, ports, HTTPS/domain, backup

| Status  | Detail                                                             |
| ------- | ------------------------------------------------------------------ |
| ✅ Done | Survey JSON files exist for all chapters (`config/surveys/`)       |
| ✅ Done | SurveyJS rendering with theme support                              |
| ✅ Done | Chapter model with JSON storage                                    |
| 🔲 TODO | Verify/complete survey definitions for all use cases               |
| 🔲 TODO | Add/remove logic (e.g. adding a second inverter, removing battery) |
| 🔲 TODO | Validation and conditional dependencies between chapters           |

### 2b: Generate compose.yaml and .env from configuration

Transform stored chapter data into a complete, runnable Docker stack (Scenarios A + B):

- Generate `compose.yaml` with all required services based on user's configuration
- Generate `.env` with all environment variables, auto-generated secrets
- Services: PostgreSQL, Redis, InfluxDB, Dashboard, Power-Splitter, Forecast-Collector, Watchtower, hardware collectors (SENEC, Shelly, MQTT)
- Only include services that match the user's configuration

| Status  | Detail                                                                          |
| ------- | ------------------------------------------------------------------------------- |
| ✅ Done | `StackBuilder` generates MVP services (4 services)                              |
| ✅ Done | `Compose::File` and `Env::File` handle reading/writing                          |
| 🔲 TODO | Extend `StackBuilder` for all services based on chapters                        |
| 🔲 TODO | Conditional service inclusion (e.g. Shelly collector only if Shelly configured) |
| 🔲 TODO | Secret generation for all required credentials                                  |
| 🔲 TODO | Service dependency management (depends_on, healthchecks)                        |

### 2c: Import existing configuration

Enable existing SOLECTRUS users to bring their installation under Helios management (Scenario C):

- Read existing `compose.yaml` and `.env` files
- Reverse-map configuration into chapter data
- Detect which devices/services are configured
- Preserve custom services and unknown variables

| Status  | Detail                                                        |
| ------- | ------------------------------------------------------------- |
| ✅ Done | `Compose::File` can parse existing compose.yaml               |
| ✅ Done | `Env::File` can parse existing .env with comment preservation |
| 🔲 TODO | Reverse mapping: .env variables → chapter data                |
| 🔲 TODO | Service detection: which devices are configured               |
| 🔲 TODO | UI flow for existing installation onboarding                  |
| 🔲 TODO | Conflict handling (manual edits vs. Helios-managed)           |

### 2d: Sensor mapping (advanced)

Map SOLECTRUS sensors to InfluxDB measurements/fields (all scenarios, but especially important for Scenario C with custom data structures).

**How it works:**

1. User connects data source (ioBroker/Home Assistant/MQTT) to InfluxDB
2. Data flows into InfluxDB with various measurements/fields
3. User opens Helios → Sensor Mapping
4. Helios queries InfluxDB for available measurements and fields
5. User maps each SOLECTRUS sensor to a measurement/field combination
6. Helios writes mappings to `.env`

**InfluxDB discovery:**

```flux
import "influxdata/influxdb/schema"
schema.measurements(bucket: "solectrus")
schema.fieldKeys(bucket: "solectrus", measurement: "pv")
```

**Sensor registry (~40 sensors):**

| Category   | Sensors                                                                                           |
| ---------- | ------------------------------------------------------------------------------------------------- |
| Inverter   | `INVERTER_POWER`, `INVERTER_POWER_1`…`_5`, `GRID_IMPORT_POWER`, `GRID_EXPORT_POWER`, `GRID_EXPORT_LIMIT`, `CASE_TEMP`, `SYSTEM_STATUS`, `SYSTEM_STATUS_OK` |
| Battery    | `BATTERY_SOC`, `BATTERY_CHARGING_POWER`, `BATTERY_DISCHARGING_POWER`                              |
| Consumers  | `HOUSE_POWER`, `HEATPUMP_POWER`, `CUSTOM_POWER_01`…`_20`                                         |
| Wallbox/EV | `WALLBOX_POWER`, `WALLBOX_CAR_CONNECTED`, `CAR_BATTERY_SOC`                                       |
| Heat pump  | `HEATPUMP_HEATING_POWER`, `HEATPUMP_TANK_TEMP`, `HEATPUMP_STATUS`, `OUTDOOR_TEMP`                |
| Forecasts  | `INVERTER_POWER_FORECAST`, `INVERTER_POWER_FORECAST_CLEARSKY`, `OUTDOOR_TEMP_FORECAST`            |

Each sensor is mapped to a measurement + field combination and stored in `.env`:

```bash
INVERTER_POWER_MEASUREMENT=pv
INVERTER_POWER_FIELD=power
```

| Status  | Detail                                                        |
| ------- | ------------------------------------------------------------- |
| 🔲 TODO | InfluxDB discovery (query available measurements/fields)      |
| 🔲 TODO | Sensor registry with all ~40 SOLECTRUS sensors                |
| 🔲 TODO | Mapping UI with dropdowns                                     |
| 🔲 TODO | Store mappings in .env (e.g. `INVERTER_POWER_MEASUREMENT=pv`) |

---

## Phase 3: Polish & Operations

**Goal:** Production-ready with operational tools and multi-language support.

- System status: Simple health indicator ("Everything OK" / "Problem detected") with alerts (FR-6)
- Log viewer: View, filter, search, and stream container logs (FR-7)
- Update management: Watchtower integration, "Update now" button, changelog display (FR-8)
- Localization: German + English UI (NFR-6)
- Telemetry: Opt-in usage statistics via `update.solectrus.de` (NFR-7)
- Link to running Dashboard from Helios UI
- Existing installation detection on first access
- Error UX: Clear messages with suggested solutions
- Mobile-responsive refinements
