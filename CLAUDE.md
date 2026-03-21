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

## External References

For daisyUI components, fetch the official LLM documentation:
https://daisyui.com/llms.txt

For SurveyJS form configuration (question types, visibleIf, validators, expressions), fetch:
https://surveyjs.io/form-library/documentation/overview

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
- System tests use `capybara-playwright-driver` (Capybara DSL + Playwright browser)
- All tests run via `bin/rspec` – no separate E2E framework
- Use `HEADLESS=false` for debugging with visible browser
- Real Docker for integration tests

## Current Phase

**Phase 2: Configuration** - Full web-based configuration of SOLECTRUS (nearly complete)

Phase 0, Phase 1, and most of Phase 2 are complete. Core functionality works:
compose.yaml/env handling, Docker API, Compose CLI, authentication, setup wizard,
service management dashboard with real-time updates, survey-based configuration,
full stack generation (14 services), import of existing installations, sensor mapping.

Remaining work:

- 2a: Cross-chapter validation and dependency checks
- 2c: Summary/review view after auto-import; web editor for unmanaged services
- 2d: InfluxDB discovery (auto-query available measurements/fields)
