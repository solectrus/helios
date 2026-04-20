# ADR-0004: Hybrid Docker Access (API + CLI)

## Status

Accepted

## Context

HELIOS needs to:

1. Read container status, health, and logs
2. Execute Docker Compose operations (up, down, pull, restart)

Options:

1. Docker API only (via `docker-api` gem)
2. CLI only (shell out to `docker` commands)
3. Hybrid approach

## Decision

Use a hybrid approach:

- **`docker-api` gem** for container inspection (status, health, logs)
- **CLI via `Open3`** for Docker Compose operations

## Consequences

**Positive:**

- Best of both worlds
- Clean Ruby API for container info
- Full Compose functionality via CLI
- Compose CLI handles YAML parsing, dependencies, networks

**Negative:**

- Two different interfaces to maintain
- CLI parsing may be fragile

**Implementation:**

```ruby
# Container info via API
Docker::Container.all
container.logs(stdout: true, tail: 100)

# Compose operations via CLI
Open3.capture3('docker', 'compose', 'up', '-d', chdir: stack_path)
```

**Rationale:**
The `docker-api` gem cannot execute `docker compose` commands. Compose operations involve YAML parsing, service dependencies, and network setup that only the Compose CLI handles correctly.
