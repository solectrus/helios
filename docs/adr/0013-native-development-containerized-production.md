# ADR-0013: Native Rails in Development, Container in Production

## Context

HELIOS's production deployment model is special: HELIOS runs *inside* the same Docker Compose stack it manages. It reads the host's Docker socket, edits the stack's `compose.yaml` and `.env`, and restarts sibling containers. Reproducing that exact topology in development would mean running HELIOS in a container, mounting the repo for live reload, exposing Vite, wiring up a dev-only compose file, and still needing a second Docker context for the "managed" stack.

Options considered:

1. Full Docker Compose for dev (HELIOS-in-a-container + managed stack)
2. Dev Container (VS Code style) with everything inside
3. Native Rails on the host, managed stack as a directory under the repo

## Decision

In development, run HELIOS **natively** on the host (`bin/dev` starts Rails + Vite + Caddy); the managed stack lives at `./stack/` and is operated via the Docker CLI on the host.

In production, HELIOS runs inside the stack as a regular Compose service ([Dockerfile](../../Dockerfile)), with the Docker socket bind-mounted in so it can control its siblings — including itself, via Watchtower (ADR-0005).

Two small consequences of this split are baked into the code:

- **Project name derivation** — in production, HELIOS reads its own container labels to discover the Compose project name; in development, it falls back to the stack directory's basename. See [docs/guides/development.md](../guides/development.md).
- **Stack path** — `/data` in production (bind-mounted from the host), `./stack` in development (relative to the Rails root).

## Consequences

**Positive:**

- Dev loop is just Rails: fast boot, real debugger, Vite HMR, native file watching
- No Docker socket mount dance in development — the dev host already has Docker
- No duplicated Compose setup to keep in sync with production
- Tests can spin up real containers against the host's Docker without extra plumbing (see ADR-0004)

**Negative:**

- Production's "HELIOS manages the stack it's part of" topology is not exercised in day-to-day dev — bugs specific to that setup (self-restart, label lookup, socket access) only surface in staging or production
- Two code paths for project-name and stack-path resolution must be kept working
- Development requires a local Ruby and Node toolchain on the host, not just Docker — acceptable trade-off given the Rails-native stack (ADR-0007)
