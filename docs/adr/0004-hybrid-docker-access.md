# ADR-0004: Hybrid Docker Access (API + CLI + Events)

## Context

HELIOS needs to:

1. Read container status, health, and logs
2. Execute Docker Compose operations (up, down, pull, restart)
3. React to container state changes in the UI without per-request polling

Options:

1. Docker API only (via `docker-api` gem)
2. CLI only (shell out to `docker` commands)
3. Hybrid approach

## Decision

Use a hybrid approach with three pillars:

- **`docker-api` gem** for container inspection (status, health, logs)
- **CLI via `Open3`** for Docker Compose operations
- **Docker events stream** (`GET /events`) for live UI updates, consumed by [`Orchestration::EventsListener`](../../app/services/orchestration/events_listener.rb) in a background thread and broadcast via Turbo Streams

## Consequences

**Positive:**

- Best of both worlds
- Clean Ruby API for container info
- Full Compose functionality via CLI
- Compose CLI handles YAML parsing, dependencies, networks
- Event stream drives the UI without per-request polling and doubles as a reconciliation mechanism for jobs lost on restart (see [ADR-0012](0012-in-process-background-jobs.md))

**Negative:**

- Three different interfaces to maintain
- CLI parsing may be fragile
- The event listener runs as a long-lived thread inside Puma and must be managed across boot/shutdown/reload (see [`config/initializers/docker_events.rb`](../../config/initializers/docker_events.rb))

**Implementation:**

```ruby
# Container info via API
Docker::Container.all
container.logs(stdout: true, tail: 100)

# Compose operations via CLI
Open3.capture3('docker', 'compose', 'up', '-d', chdir: stack_path)

# Events stream drives live UI updates
Orchestration::EventsListener.start
```

**Rationale:**
The `docker-api` gem cannot execute `docker compose` commands. Compose operations involve YAML parsing, service dependencies, and network setup that only the Compose CLI handles correctly. The events listener complements both by turning Docker's push-based event stream into live Turbo Stream updates, so the UI does not have to poll per request.
