# Development Guide

## Prerequisites

- Ruby (see [`.ruby-version`](../../.ruby-version))
- Node.js with Yarn (pinned via `packageManager` in [`package.json`](../../package.json); installed by Corepack)
- Docker Desktop or Docker Engine
- Docker Compose CLI
- [Caddy](https://caddyserver.com/) — terminates TLS for `https://helios.localhost` in development

## Setup

1. Install native dependencies from the [Brewfile](../../Brewfile):

   ```bash
   brew bundle
   ```

2. Install gems, NPM packages, and create the database:

   ```bash
   bin/setup
   ```

## Configuration

**Stack path** (`Rails.configuration.data_path`):

- Production: `/data` (bind-mounted from the host stack directory)
- Development: `./stack` (relative to Rails root)
- Test: `./spec/fixtures`

**Project name:** HELIOS hard-codes the Compose project name to `solectrus` (see [`Orchestration::PROJECT_NAME`](../../app/services/orchestration.rb)). On boot, [`StartupCheck#check_compose_project_name`](../../app/services/startup_check.rb) refuses to run if `compose.yaml` does not declare `name: solectrus`. The `stack/compose.yaml` checked into this repo already has that line — leave it in place.

This keeps container lookups by `com.docker.compose.project` label stable regardless of the host directory name.

## Development Workflow

Start all processes (Rails + Vite + Caddy) and open the app in your default browser:

```bash
bin/dev
```

The app is served at https://helios.localhost (via Caddy reverse proxy). On the first run, Caddy will ask for your password to install its local CA certificate.

**Key difference from production:**

- Production: HELIOS runs as a container inside the stack it manages; `docker.sock` is bind-mounted in.
- Development: HELIOS runs natively on the host and talks to the local `docker.sock` directly — no container, no socket mount needed.

Both modes use the same hybrid Docker access (docker-api gem + `docker compose` CLI + events listener). Stack detection via `com.docker.compose.project=solectrus` labels works identically in both.

---

## Testing

**Frameworks:** RSpec for Ruby code, Bats for shell scripts

### Test Strategy

**Core principles:**

- All code must be covered by tests
- 100% coverage is the goal (not enforced, but aspired to)
- Focus on **unit tests** – they are fast, reliable, and document behavior
- Use **real Docker** in tests, not mocks — [`spec/support/docker_helpers.rb`](../../spec/support/docker_helpers.rb) exposes `skip_without_docker` for tests that need a running daemon
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
| Shell tests   | Bootstrap installer, shell scripts  | Bats                          | Medium   |

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

# Run shell script tests (Bats)
bats --recursive spec/bats/
```

SimpleCov runs unconditionally from [`spec/spec_helper.rb`](../../spec/spec_helper.rb) and writes the coverage report to `coverage/index.html`.

### Test Structure

`spec/` mirrors `app/`. Roughly:

- `spec/models/`, `spec/services/`, `spec/jobs/`, `spec/channels/`, `spec/lib/` — unit tests, one file per class / module
- `spec/requests/` — HTTP-level specs per controller (plus nested folders for nested controllers)
- `spec/system/` — Playwright-driven smoke coverage; keep thin, most flows are covered at the request level
- `spec/frontend/` — Vitest specs for Stimulus controllers and frontend utils
- `spec/bats/` — Bats specs for shell scripts (e.g. `spec/bats/bootstrap/` for the bootstrap installer)
- `spec/fixtures/import_scenarios/` — real `compose.yaml` / `.env` samples driving the Scenario C auto-import tests
- `spec/support/` — RSpec helpers and shared setup

### Writing Good Tests

- Test behavior, not implementation
- One assertion per test when possible
- Use descriptive test names: `it "preserves comments when saving"`
- Use fixtures for file-based tests
- Clean up Docker resources after integration tests
- Use system tests (`spec/system/`) for anything that requires real browser JavaScript execution
