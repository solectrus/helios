# HELIOS

Rails 8.1 web-based management tool for SOLECTRUS Docker hosts.

## Stack

- Ruby 4.0, SQLite3
- Hotwire (Turbo + Stimulus), TypeScript, Vite, ViewComponent
- Tailwind CSS v4, ERB templates, daisyUI
- RSpec + Playwright

## Documentation

Detailed documentation lives in `docs/`:

- `docs/spec/requirements.md` - Functional and non-functional requirements
- `docs/guides/phases.md` - Development phases and current scope
- `docs/guides/development.md` - Setup, workflow, and test strategy
- `docs/architecture/overview.md` - System architecture and install script
- `docs/architecture/docker.md` - Docker integration, generated files, error handling
- `docs/adr/` - Architecture decision records

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

## Frontend

- Stimulus controllers use **TypeScript** (`.ts` files), not JavaScript
- UI components use daisyUI (Tailwind CSS component library)

## Testing

### Running Tests

- Model specs: `bin/rspec spec/models/<model>_spec.rb`
- Request specs: `bin/rspec spec/requests/<feature>_spec.rb`
- System specs: `bin/rspec spec/system/<feature>_spec.rb`

**System specs are slow** (Playwright browser automation). Only run when:

- UI behavior or JavaScript interactions are affected
- Request specs cannot verify the functionality

Use `HEADLESS=false` for debugging with a visible browser window.

### Test Guidelines

- 100% coverage is the goal (not enforced)
- Focus on unit tests
- Use real Docker in tests, no mocking
- System tests use `capybara-playwright-driver` (Capybara DSL + Playwright browser)
