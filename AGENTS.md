# HELIOS

Rails 8.1 web-based management tool for SOLECTRUS Docker hosts. Removes the need to hand-edit `compose.yaml` / `.env` or run `docker compose` commands.

## Stack

- Ruby 4.0, SQLite3
- Hotwire (Turbo + Stimulus in TypeScript), Vite, ViewComponent
- Tailwind CSS v4, ERB, daisyUI
- RSpec + Playwright, Vitest, Bats

## Documentation

See `docs/README.md` for the full map. Key entry points: `docs/product.md`, `docs/architecture/`, `docs/guides/development.md`, `docs/adr/`.

## External References

Fetch on demand:

- daisyUI: https://daisyui.com/llms.txt
- SurveyJS: https://surveyjs.io/form-library/documentation/overview
- SOLECTRUS env var semantics: https://docs.solectrus.de/ — **source of truth** for `INFLUX_*`, `FORECAST_*`, `SENEC_*`, `MQTT_*`, `SHELLY_*`, `POWER_SPLITTER_*`, `WATCHTOWER_*` defaults/ranges. Don't infer from existing HELIOS code; it may be wrong.

## Verifying in the Browser

Verify non-trivial UI changes — new flows, complex interactions, anything where rendering or console errors aren't obvious from the diff — against the dev UI at https://helios.localhost using the Chrome DevTools MCP tools (`chrome-devtools-mcp` plugin). The dev server is already running (started by the user via `bin/dev`); do **not** start it yourself. Skip for typos, simple CSS tweaks, obvious copy edits.

## Mandatory Linting

After modifying code, **always** run the matching linter(s) and fix issues:

- Ruby (`.rb`, `.rake`, `Gemfile`, `config.ru`): `bin/rubocop --autocorrect`
- ERB (`.erb`, including `.turbo_stream.erb`): `bun run erb:format` (or `erb:check`) + `bin/herb lint`
- TypeScript / JavaScript (`.ts`, `.js`, `.mjs`, `.mts`): `bun run lint`, plus `bun run tsc` for `.ts`
- Shell (`.sh`): `shellcheck`
- JSON/YAML/Markdown/CSS: `bunx prettier --write`

Run them before you call the change done. `bin/brakeman` occasionally for security scans, not per change.

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

Copy rules for user-facing text:

- No Docker vocabulary (container, image, volume). Speak of "Dienst" / "service" instead
- No second-person address (du/dein, you/your) and no formal "Sie" either. Phrase impersonally
- German uses "Protokoll(e)", not the anglicism "Logs" (English keeps "Logs")
- No em dashes. Use a comma or rephrase (commit messages, code comments and license texts are exempt)

## Project-Specific Rules

- Bind mounts, not Docker volumes (ADR-0003)
- HELIOS writes only two external files: `compose.yaml` and `.env`
- Preserve comments and unknown vars in `.env` (comments in `compose.yaml` are not preserved)
- Everything the user configures lives in `config.yaml` (ADR-0009). Active Record / SQLite holds only operational records HELIOS produces at runtime (`Backup`, `RunnerLog`) plus Solid Cable
- Changing the `config.yaml` layout requires a `ConfigurationMigrations::` migration (ADR-0014); moving or renaming a field without one silently drops existing users' values
- After a config-schema or compose-export change, run `bin/rake fixtures:regenerate` and keep the snapshot churn minimal

## Testing

- `bin/rspec [path]` — Ruby specs; `bun run test` — Vitest (`spec/frontend/`); `bats --recursive spec/bats/` — shell scripts
- `spec/integration/` drives real Docker stacks, is auto-tagged `:integration` and is skipped by a bare `bin/rspec`. Run it explicitly: `bin/rspec --tag integration`
- Use real Docker, no mocking
- Parallel runs (`bin/turbo_tests`, `bin/ci`, CI): a spec writing to a fixed disk path must scope it per process with `TEST_ENV_NUMBER` (e.g. `tmp/stack#{ENV.fetch('TEST_ENV_NUMBER', nil)}`), or it clobbers other workers. `bin/coverage` collates the SimpleCov reports afterwards
- Aim for high coverage, but don't chase 100% — tests proportional to complexity, focused on unit and request specs. The only system spec is `spec/system/smoke_spec.rb` (Playwright); usually no need to touch it
- Test structure and further details: `docs/guides/development.md`
