# HELIOS

Rails 8.1 web-based management tool for SOLECTRUS Docker hosts. HELIOS removes the need to hand-edit `compose.yaml` / `.env` or run `docker compose` commands.

## Stack

- Ruby 4.0, SQLite3
- Hotwire (Turbo + Stimulus), TypeScript, Vite, ViewComponent
- Tailwind CSS v4, ERB templates, daisyUI
- RSpec + Playwright, Bats for shell scripts

## Documentation

Documentation lives in `docs/` (see `docs/README.md` for the full map):

**What HELIOS does:**

- `docs/product.md` - Scenarios, features, technical constraints

**How HELIOS is built:**

- `docs/architecture/overview.md` - System architecture and internal storage
- `docs/architecture/docker.md` - Docker integration, generated files, health checks
- `docs/guides/development.md` - Setup, workflow, and test strategy
- `docs/adr/` - Architecture decision records

**What's left:**

- `docs/todos.md` - Open work items, grouped by area

## External References

For daisyUI components, fetch the official LLM documentation:
https://daisyui.com/llms.txt

For SurveyJS form configuration (question types, visibleIf, validators, expressions), fetch:
https://surveyjs.io/form-library/documentation/overview

For SOLECTRUS env var semantics (defaults, valid ranges, runtime behavior), fetch:
https://docs.solectrus.de/

This is the source of truth when picking default values, validation bounds,
or fallback behavior for any `INFLUX_*`, `FORECAST_*`, `SENEC_*`, `MQTT_*`,
`SHELLY_*`, `POWER_SPLITTER_*`, or `WATCHTOWER_*` setting HELIOS exports.
Do not infer defaults from the existing HELIOS code — they may be wrong (e.g.
HELIOS used to hardcode `POWER_SPLITTER_INTERVAL=300`, the documented
minimum, while the docs default is `3600`).

## Code Quality

```bash
bin/rubocop           # Ruby style (use --autocorrect for auto-correct)
bin/herb lint         # ERB template linting
bin/yarn erb:format   # ERB formatting (auto-fix)
bin/yarn erb:check    # ERB formatting check
bin/yarn tsc          # TypeScript type checking
bin/yarn lint         # ESLint for TypeScript
bin/brakeman          # Security scan (run occasionally, not per-change)
bin/rspec             # Tests
```

### Mandatory Linting

After creating or modifying code, **always** run the relevant linter(s) before considering the task complete. Fix any issues found.

- **Ruby code** (`.rb`): Run `bin/rubocop` on changed files. Use `--autocorrect` to auto-correct, review the result.
- **ERB templates** (`.html.erb`): Run `bin/herb lint` for linting. Run `bin/yarn erb:format` to auto-fix formatting or `bin/yarn erb:check` to check only.
- **TypeScript code** (`.ts`): Run `bin/yarn tsc` (type checking) and `bin/yarn lint` (ESLint). Both must pass.

## Rails Conventions

- **Controllers**: Always use plural names (e.g., `SetupsController`, not `SetupController`)
- **Routes**: Only use the 7 standard RESTful actions (`index`, `show`, `new`, `create`, `edit`, `update`, `destroy`)
- **Custom actions**: Model as nested resources instead of custom member/collection routes
  - Example: Instead of `post :start` on services, use `Services::StartsController#create`
  - This keeps routing RESTful and controllers focused

## Frontend

- Stimulus controllers use **TypeScript** (`.ts` files), not JavaScript
- UI components use daisyUI (Tailwind CSS component library)

## Project-Specific Rules

- Use bind mounts, not Docker volumes (ADR-0003)
- Use real Docker in tests, no mocking
- Only write two external files HELIOS manages: `compose.yaml` and `.env`
- All user configuration is stored in a single `config.yaml` file (ADR-0009); no Active Record tables are used for app data
- Preserve comments and unknown variables in `.env`
- Comments in `compose.yaml` are not preserved (acceptable)

## Testing

### Running Tests

- Model specs: `bin/rspec spec/models/<model>_spec.rb`
- Request specs: `bin/rspec spec/requests/<feature>_spec.rb`
- System specs: `bin/rspec spec/system/<feature>_spec.rb`
- Shell script specs: `bats --recursive spec/bats/`

**System specs are slow** (Playwright browser automation). Only run when:

- UI behavior or JavaScript interactions are affected
- Request specs cannot verify the functionality

Use `HEADLESS=false` for debugging with a visible browser window.

### Test Guidelines

- 100% coverage is the goal (not enforced)
- Focus on unit tests
- Use real Docker in tests, no mocking
- System tests use `capybara-playwright-driver` (Capybara DSL + Playwright browser)

## Project Status

HELIOS is nearly feature-complete. Core functionality is shipped: compose.yaml / .env
handling with comment-preserving round-trip, YAML-based configuration (ADR-0009), hybrid
Docker integration (Docker API + Compose CLI + events listener), authentication, first-start
consent flow, survey-based configuration (15 survey JSONs), service management dashboard
with live status bar and log viewer, full stack generation (~15 service definitions under
`Export::Services::*`), auto-import of existing installations with unmanaged preservation,
sensor mapping with InfluxDB latest-value readings, DE/EN localization.

Remaining work is tracked by area in `docs/todos.md` — auto-import review screen, InfluxDB
discovery during import, "Update now" trigger for Watchtower, and a link from Dashboard
back to HELIOS.
