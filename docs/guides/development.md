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
# Default: /opt/solectrus (production)
# Development: configurable via environment variable
HELIOS_STACK_PATH=./tmp/solectrus-stack
```

**Project name derivation:**

- In production (container): Helios reads project name from its own container labels
- In development (native): Project name is derived from the directory name of `HELIOS_STACK_PATH`

Example: `HELIOS_STACK_PATH=./tmp/solectrus-stack` → project name is `solectrus-stack`

This matches Docker Compose's default behavior (using directory name as project name).

## Development Workflow

```bash
# 1. Start Rails app locally
bin/rails server -p 3999

# 2. Helios creates/manages compose.yaml in HELIOS_STACK_PATH
# 3. Helios runs `docker compose` commands against that directory
# 4. Stack services run in Docker, Helios runs natively
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
     /      \    Integration tests – Docker API, CLI interactions
    /--------\
   /          \  Unit tests – majority of tests, fast, isolated
  --------------
```

### Test Categories

| Category          | Purpose                              | Tools               | Priority |
| ----------------- | ------------------------------------ | ------------------- | -------- |
| Unit tests        | Service classes, models              | RSpec               | High     |
| Integration tests | Docker API, Compose CLI interactions | RSpec + real Docker | Medium   |
| System tests      | Full UI flows (Phase 1+)             | RSpec + Capybara    | Low      |

**What we don't use:**

- No JavaScript tests with Playwright, Cypress, or similar – the effort doesn't pay off for this project
- Capybara with Rack driver is sufficient for UI testing

### Run Tests

```bash
# Run all tests
bin/rspec

# Run specific test file
bin/rspec spec/services/env_file_spec.rb

# Run with coverage report
COVERAGE=true bin/rspec
```

### Phase 0 Focus

- Unit tests for `ComposeFile`, `EnvFile` classes
- Integration tests for `DockerClient`, `ComposeRunner`
- Tests run against real Docker (no mocking of Docker API)

### Test Structure

```
spec/
├── services/
│   ├── compose_file_spec.rb
│   ├── env_file_spec.rb
│   ├── docker_client_spec.rb
│   └── compose_runner_spec.rb
├── models/
│   └── configuration_spec.rb
├── fixtures/
│   ├── sample.env
│   └── sample-compose.yaml
└── support/
    └── docker_helpers.rb
```

### Writing Good Tests

- Test behavior, not implementation
- One assertion per test when possible
- Use descriptive test names: `it "preserves comments when saving"`
- Use fixtures for file-based tests
- Clean up Docker resources after integration tests
