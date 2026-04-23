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

`spec/` mirrors `app/`. Roughly:

- `spec/models/`, `spec/services/`, `spec/jobs/`, `spec/channels/`, `spec/lib/` — unit tests, one file per class / module
- `spec/requests/` — HTTP-level specs per controller (plus nested folders for nested controllers)
- `spec/system/` — Playwright-driven smoke coverage; keep thin, most flows are covered at the request level
- `spec/frontend/` — Vitest specs for Stimulus controllers and frontend utils
- `spec/fixtures/import_scenarios/` — real `compose.yaml` / `.env` samples driving the Scenario C auto-import tests
- `spec/support/` — RSpec helpers and shared setup

### Writing Good Tests

- Test behavior, not implementation
- One assertion per test when possible
- Use descriptive test names: `it "preserves comments when saving"`
- Use fixtures for file-based tests
- Clean up Docker resources after integration tests
- Use system tests (`spec/system/`) for anything that requires real browser JavaScript execution
