# ADR-0012: In-Process Background Jobs (no external queue)

## Context

HELIOS runs a handful of long-ish Docker operations asynchronously — `docker compose up`, `pull`, `restart`, log tailing, orphan cleanup. These are enqueued as ActiveJob jobs. Options considered:

1. Sidekiq (Redis-backed)
2. SolidQueue (DB-backed, what Rails 8 ships with by default)
3. ActiveJob `:async` adapter (in-process thread pool)

We previously used SolidQueue but dropped it (see commit `c388df4`).

## Decision

Use ActiveJob's `:async` adapter in both development and production. Jobs execute on a thread pool inside the same Puma process.

This is only acceptable because of two invariants:

1. **Jobs are always user-initiated.** Nothing enqueues a job on a schedule or from a webhook — every job is a reaction to a button click or a form submission.
2. **Docker is the source of truth, not HELIOS.** If a job is lost on restart (because Puma dies mid-flight), the Docker daemon still holds the real state. [`EventsListener`](../../app/services/orchestration/events_listener.rb) subscribes to the Docker events stream and reconciles the UI on next boot. HELIOS does not need durable job storage because it never owns state that Docker doesn't already have.

## Consequences

**Positive:**

- No Redis, no worker processes, no schema migrations for a job queue
- One process (Puma) to monitor, restart, and log
- Lower resource footprint — relevant on Raspberry Pi
- Simpler deploy: `docker compose up helios` is enough

**Negative:**

- A crash or redeploy during a running job drops the job silently — acceptable because Docker keeps running and `EventsListener` re-syncs the UI on boot
- Jobs share Puma's thread pool; a flood of long jobs could starve web requests (not a realistic risk for this user count)
- No job retry/backoff machinery — jobs are expected to either succeed or surface errors to the user immediately
- Not suitable if HELIOS ever grows scheduled/background work it truly _owns_ (e.g. polling external APIs on a timer); that would invalidate invariant (1) and require revisiting this decision
