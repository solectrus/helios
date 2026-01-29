# Helios - AI Assistant Instructions

## Project

Helios is a web-based bootstrap helper for SOLECTRUS. It manages Docker Compose stacks through a web interface.

## Documentation

**Start here:**

- [docs/spec/requirements.md](docs/spec/requirements.md) - Functional and non-functional requirements
- [docs/guides/phases.md](docs/guides/phases.md) - Development phases and current scope
- [docs/guides/development.md](docs/guides/development.md) - Setup, workflow, and test strategy

**Architecture:**

- [docs/architecture/overview.md](docs/architecture/overview.md) - System architecture and install script
- [docs/architecture/docker.md](docs/architecture/docker.md) - Docker integration, generated files, error handling

**ADRs:** [docs/adr/](docs/adr/) - All architecture decisions

## Project-Specific Rules

- Use bind mounts, not Docker volumes (ADR-0003)
- Use real Docker in tests, no mocking
- Only write two external files: `compose.yaml` and `.env`
- All configuration is stored in SQLite as JSON blob
- Preserve comments and unknown variables in `.env`
- Comments in `compose.yaml` are not preserved (acceptable)

## Test Strategy

- 100% coverage is the goal (not enforced)
- Focus on unit tests
- Capybara for system tests, no Playwright/Cypress
- Real Docker for integration tests

## Current Phase

**Phase 0: Proof of Concept** - Technical validation without UI

Goal: Validate core functionality via `rails console`:

1. Read/write `compose.yaml`
2. Read/write `.env` (preserving comments)
3. Access Docker API (container status, logs)
4. Execute Compose commands (up, down, pull, restart)
