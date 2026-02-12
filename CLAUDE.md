# Helios - AI Assistant Instructions

## Project

Helios is a web-based management tool for SOLECTRUS, aimed at the admin of the Docker host. It eliminates the need to manually edit `compose.yaml` and `.env` files or run Docker commands.

## Documentation

**Start here:**

- [docs/spec/requirements.md](docs/spec/requirements.md) - Functional and non-functional requirements
- [docs/guides/phases.md](docs/guides/phases.md) - Development phases and current scope
- [docs/guides/development.md](docs/guides/development.md) - Setup, workflow, and test strategy

**Architecture:**

- [docs/architecture/overview.md](docs/architecture/overview.md) - System architecture and install script
- [docs/architecture/docker.md](docs/architecture/docker.md) - Docker integration, generated files, error handling

**ADRs:** [docs/adr/](docs/adr/) - All architecture decisions

## daisyUI Reference

For daisyUI components, fetch the official LLM documentation:
https://daisyui.com/llms.txt

## Code Quality

- All code must pass `bin/rubocop` without offenses
- Run Rubocop before considering any code change complete
- Use `bin/rubocop --autocorrect` for automatic fixes

## Rails Conventions

- **Controllers**: Always use plural names (e.g., `SetupsController`, not `SetupController`)
- **Routes**: Only use the 7 standard RESTful actions (`index`, `show`, `new`, `create`, `edit`, `update`, `destroy`)
- **Custom actions**: Model as nested resources instead of custom member/collection routes
  - Example: Instead of `post :start` on services, use `Services::StartsController#create`
  - This keeps routing RESTful and controllers focused

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

**Phase 1: MVP** - First usable version with web UI

Phase 0 (Proof of Concept) is complete. All core functionality works:
compose.yaml/env handling, Docker API, Compose CLI, authentication, setup wizard,
service management with real-time updates.

Current focus: completing the MVP user flow (install script → setup → running stack).
