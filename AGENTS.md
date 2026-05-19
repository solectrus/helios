# HELIOS

Rails 8.1 web-based management tool for SOLECTRUS Docker hosts. Removes the need to hand-edit `compose.yaml` / `.env` or run `docker compose` commands.

## Stack

- Ruby 4.0, SQLite3
- Hotwire (Turbo + Stimulus in TypeScript), Vite, ViewComponent
- Tailwind CSS v4, ERB, daisyUI
- RSpec + Playwright, Bats

## Documentation

See `docs/README.md` for the full map. Key entry points: `docs/product.md`, `docs/architecture/`, `docs/guides/development.md`, `docs/adr/`, `docs/todos.md`.

## External References

Fetch on demand:

- daisyUI: https://daisyui.com/llms.txt
- SurveyJS: https://surveyjs.io/form-library/documentation/overview
- SOLECTRUS env var semantics: https://docs.solectrus.de/ — **source of truth** for `INFLUX_*`, `FORECAST_*`, `SENEC_*`, `MQTT_*`, `SHELLY_*`, `POWER_SPLITTER_*`, `WATCHTOWER_*` defaults/ranges. Don't infer from existing HELIOS code; it may be wrong.

## Verifying in the Browser

For non-trivial UI changes — new flows, complex interactions, anything where rendering or console errors aren't obvious from the diff — verify against the running dev UI at https://helios.localhost using the `mcp__chrome-devtools__*` tools.

Skip browser verification for trivial changes (typos, simple CSS tweaks, obvious copy edits) — it's slower and costs tokens.

Assume the dev server is already running (started by the user via `bin/dev`) — do **not** start it yourself.

## Mandatory Linting

After modifying code, **always** run the matching linter(s) and fix issues:

- Ruby (`.rb`): `bin/rubocop` (use `--autocorrect`)
- ERB (`.html.erb`): `bin/herb lint` + `bin/yarn erb:format` (or `erb:check`)
- TypeScript (`.ts`): `bin/yarn tsc` + `bin/yarn lint`
- JSON/YAML/Markdown/CSS: `bin/yarn prettier --write`

Run `bin/brakeman` occasionally for security scans (not per-change).

In Claude Code sessions these run automatically at turn end via
`.claude/hooks/` — no need to invoke them manually for edited files.

## Rails Conventions

- Controllers: plural names (`SetupsController`)
- Routes: only the 7 RESTful actions; model custom actions as nested resources (e.g. `Services::StartsController#create` instead of `post :start`)

## ViewComponent

Use ViewComponents for reusable UI; prefer them over partials. Sidecar layout per component:

```
app/components/<name>/component.rb
app/components/<name>/component.html.erb
app/components/<name>/component_controller.ts   # optional, co-located Stimulus controller
app/components/<name>/component.de.yml          # optional, co-located i18n (per locale)
app/components/<name>/component.en.yml
```

## i18n

HELIOS ships in German and English — every user-facing string must exist in both locales. Never hardcode UI text. App-wide keys live in `config/locales/{de,en}.yml`; component-local keys use the ViewComponent sidecar (`app/components/<name>/component.{de,en}.yml`).

## Project-Specific Rules

- Bind mounts, not Docker volumes (ADR-0003)
- HELIOS writes only two external files: `compose.yaml` and `.env`
- All app data lives in `config.yaml` (ADR-0009); no Active Record tables
- Preserve comments and unknown vars in `.env` (comments in `compose.yaml` are not preserved)

## Testing

- Ruby/request specs: `bin/rspec spec/<models|requests>/<file>_spec.rb`
- Frontend specs (Stimulus controllers, TS utils): `bin/yarn test` (Vitest, in `spec/frontend/`)
- Shell scripts: `bats --recursive spec/bats/`
- Integration specs (`spec/integration/`): slow, drive a real stack via Docker. Auto-tagged `:integration`; run by `bin/ci` (which sets `CI`) and on GitHub CI. A bare `bin/rspec` skips them — run them alone with `bin/rspec --tag integration`.
- Use real Docker, no mocking
- Specs run in parallel via `bin/turbo_tests` (on CI and in `bin/ci`); `bin/coverage` then collates a single SimpleCov report. A spec writing to a fixed disk path must scope it per process with `TEST_ENV_NUMBER` (e.g. `tmp/stack#{ENV.fetch('TEST_ENV_NUMBER', nil)}`), or it will clobber other processes.
- Aim for high coverage, but don't chase 100% — write tests proportional to the code's complexity, no tests for trivial wiring. Focus on unit and request specs. The only system spec is `spec/system/smoke_spec.rb` (Playwright); usually no need to touch it.
