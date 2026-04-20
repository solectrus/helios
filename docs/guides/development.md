# Development Guide

## Prerequisites

See [Architecture Overview](../architecture/overview.md) for versions.

- Ruby
- Node.js
- Docker Desktop or Docker Engine
- Docker Compose CLI

## Setup

```bash
bin/setup
```

## Configuration

**Stack path:**

- In production: `/data` (mounted from host via Docker volume)
- In development: `./stack` (relative to Rails root)

**Project name derivation:**

- In production (container): HELIOS reads project name from its own container labels
- In development (native): Project name is derived from the directory name of the stack path

Example: `./stack` → project name is `stack`

This matches Docker Compose's default behavior (using directory name as project name).

## Development Workflow

```bash
# Start all processes (Rails + Vite + Caddy)
bin/dev

# URL: https://helios.localhost (via Caddy reverse proxy)
```

**Key difference from production:**

- Production: HELIOS runs inside the stack it manages
- Development: HELIOS runs outside, manages stack via CLI

**Docker access:**

- Uses Docker CLI directly (same as production)
- No socket mounting needed (native access on host)
- Stack detection via labels still works

---

## Testing

**Framework:** RSpec

### Test Strategy

**Core principles:**

- All code must be covered by tests
- 100% coverage is the goal (not enforced, but aspired to)
- Focus on **unit tests** – they are fast, reliable, and document behavior
- Write tests first or alongside implementation, not as an afterthought

**Test pyramid:**

```
        /\
       /  \      System tests – few, for JS-heavy and UI flows
      /----\
     /      \    Request tests – controllers, auth, integration
    /--------\
   /          \  Unit tests – majority of tests, fast, isolated
  /------------\
```

### Test Categories

| Category      | Purpose                             | Tools                         | Priority |
| ------------- | ----------------------------------- | ----------------------------- | -------- |
| Unit tests    | Service classes, models, components | RSpec                         | High     |
| Request tests | Controllers, auth, HTTP integration | RSpec                         | High     |
| Job tests     | Background job behavior             | RSpec                         | Medium   |
| System tests  | UI flows, JS-heavy interactions     | RSpec + Capybara + Playwright | Medium   |

**System tests** use `capybara-playwright-driver`: Capybara's DSL with a real Chromium browser powered by Playwright. This covers both server-rendered flows and JS-heavy interactions (SurveyJS forms, real-time updates, Stimulus controllers).

### Run Tests

```bash
# Run all tests (unit, request, job, system)
bin/rspec

# Run specific test file
bin/rspec spec/services/compose/file_spec.rb

# Run only system tests
bin/rspec spec/system/

# Run system tests with visible browser (for debugging)
HEADLESS=false bin/rspec spec/system/

# Run with coverage report
COVERAGE=true bin/rspec
```

### Test Structure

```
spec/
├── channels/                           # Action Cable
│   ├── application_cable/connection_spec.rb
│   └── logs_channel_spec.rb
├── frontend/                           # JS/Vite frontend unit tests
├── jobs/
│   ├── compose_job_spec.rb
│   └── orphaned_stop_job_spec.rb
├── lib/
│   └── startup_check_middleware_spec.rb
├── models/
│   ├── config_schema_spec.rb
│   ├── configuration_spec.rb
│   ├── sensor_mappings_spec.rb
│   └── sensor_registry_spec.rb
├── requests/
│   ├── advanced_spec.rb
│   ├── datasources_spec.rb
│   ├── files_spec.rb
│   ├── locale_spec.rb
│   ├── sensors_spec.rb
│   ├── services_spec.rb
│   ├── sessions_spec.rb
│   ├── starts_spec.rb
│   ├── configurations/
│   │   ├── settings_spec.rb
│   │   └── surveys_spec.rb
│   └── services/
│       ├── batches_spec.rb
│       ├── logs_spec.rb
│       ├── orphaned_tasks_spec.rb
│       ├── rows_spec.rb
│       └── tasks_spec.rb
├── services/
│   ├── compose/                        # compose.yaml parsing & models
│   │   ├── file_spec.rb
│   │   ├── service_spec.rb
│   │   └── service_collection_spec.rb
│   ├── env/
│   │   └── file_spec.rb
│   ├── export/                         # compose.yaml + .env generation
│   │   ├── builder_spec.rb
│   │   └── unmanaged_round_trip_spec.rb
│   ├── import/                         # Scenario C auto-import
│   │   ├── configuration_importer_spec.rb
│   │   └── configuration_importer/mqtt_extractor_spec.rb
│   ├── influx_db/
│   │   └── client_spec.rb
│   ├── orchestration/                  # Docker integration & runtime
│   │   ├── affected_services_spec.rb
│   │   ├── command_result_spec.rb
│   │   ├── connection_spec.rb
│   │   ├── container_spec.rb
│   │   ├── error_store_spec.rb
│   │   ├── event_spec.rb
│   │   ├── orphaned_services_spec.rb
│   │   ├── runner_spec.rb
│   │   ├── service_broadcaster_spec.rb
│   │   ├── stack_status_spec.rb
│   │   └── version_extractor_spec.rb
│   ├── orchestration_spec.rb
│   ├── ansi_to_html_spec.rb
│   ├── log_line_formatter_spec.rb
│   └── startup_check_spec.rb
├── system/
│   └── smoke_spec.rb
├── fixtures/
└── support/
```

### Writing Good Tests

- Test behavior, not implementation
- One assertion per test when possible
- Use descriptive test names: `it "preserves comments when saving"`
- Use fixtures for file-based tests
- Clean up Docker resources after integration tests
- Use system tests (`spec/system/`) for anything that requires real browser JavaScript execution
