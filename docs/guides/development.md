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

```bash
# Path where Helios manages compose.yaml and .env
# Default: ./stack (relative to Rails root)
# Configurable via environment variable
HELIOS_STACK_PATH=./stack
```

**Project name derivation:**

- In production (container): Helios reads project name from its own container labels
- In development (native): Project name is derived from the directory name of `HELIOS_STACK_PATH`

Example: `HELIOS_STACK_PATH=./stack` → project name is `stack`

This matches Docker Compose's default behavior (using directory name as project name).

## Development Workflow

```bash
# Start all processes (Rails + Vite + Caddy)
bin/dev

# URL: https://helios.localhost (via Caddy reverse proxy)
```

**Key difference from production:**

- Production: Helios runs inside the stack it manages
- Development: Helios runs outside, manages stack via CLI

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
       /  \      System tests (Capybara) – few, for critical flows
      /----\
     /      \    Request tests – controllers, auth, integration
    /--------\
   /          \  Unit tests – majority of tests, fast, isolated
  --------------
```

### Test Categories

| Category      | Purpose                              | Tools               | Priority |
| ------------- | ------------------------------------ | -------------------- | -------- |
| Unit tests    | Service classes, models, components  | RSpec                | High     |
| Request tests | Controllers, auth, HTTP integration  | RSpec                | High     |
| Job tests     | Background job behavior              | RSpec                | Medium   |
| System tests  | Full UI flows                        | RSpec + Capybara     | Low      |

**What we don't use:**

- No JavaScript tests with Playwright, Cypress, or similar
- Capybara with Rack driver is sufficient for UI testing

### Run Tests

```bash
# Run all tests
bin/rspec

# Run specific test file
bin/rspec spec/services/compose/file_spec.rb

# Run with coverage report
COVERAGE=true bin/rspec
```

### Test Structure

```
spec/
├── models/
│   ├── admin_spec.rb
│   ├── chapter_spec.rb
│   └── configuration_spec.rb
├── requests/
│   ├── admins_spec.rb
│   ├── configurations_spec.rb
│   ├── configurations/chapters_spec.rb
│   ├── dashboard_spec.rb
│   ├── sessions_spec.rb
│   ├── setups_spec.rb
│   └── services/
│       ├── batches_spec.rb
│       ├── rows_spec.rb
│       └── tasks_spec.rb
├── jobs/
│   └── compose_job_spec.rb
├── services/
│   ├── compose/
│   │   ├── command_result_spec.rb
│   │   ├── file_spec.rb
│   │   ├── runner_spec.rb
│   │   ├── service_spec.rb
│   │   └── service_collection_spec.rb
│   ├── env/
│   │   └── file_spec.rb
│   ├── docker_host/
│   │   └── container_spec.rb
│   ├── docker_host_spec.rb
│   └── stack_builder_spec.rb
├── fixtures/
│   └── ...
└── support/
    ├── auth_helpers.rb
    ├── docker_helpers.rb
    └── vite_helpers.rb
```

### Writing Good Tests

- Test behavior, not implementation
- One assertion per test when possible
- Use descriptive test names: `it "preserves comments when saving"`
- Use fixtures for file-based tests
- Clean up Docker resources after integration tests
