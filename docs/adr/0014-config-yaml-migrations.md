# ADR-0014: Schema Migrations for `config.yaml`

## Context

`config.yaml` is the single source of truth for all HELIOS configuration (see [ADR-0009](0009-configuration-model.md)). Its layout — section names, field names, value shapes — evolves as features land. Past schema changes simply moved fields between sections, relying on `Configuration#sanitize_sections!` to silently drop anything not declared in `ConfigSchema`.

That works for fresh installs but breaks for existing users: when a field moves to a different section, the old value is no longer in the schema, gets dropped on the next save, and the user's setting is silently lost.

We need a forward-compatible way to evolve the schema without losing user data, both for upcoming changes and for similar moves in the future.

## Decision

Introduce ActiveRecord-style migrations for `config.yaml`:

- A top-level integer key `_schema_version` tracks the schema the file was last written against. Files without the key are treated as version 0. The key is written as the first entry in the file so it stays visible at the top.
- Migrations live under `ConfigurationMigrations::` and inherit from `ConfigurationMigrations::Base`. The base class provides a small DSL — `version` for ordering, plus operation helpers (currently `move`) that build up the transformation declaratively. New operations are added to the base class as schema evolutions require them.
- Migration files in `app/services/configuration_migrations/` use a numeric filename prefix (`001_*.rb`) for chronological ordering. The directory is excluded from Zeitwerk autoload and required explicitly. Class names express the activity (`CreateDashboardSection`, not `DashboardSection`), matching ActiveRecord conventions.
- `ConfigurationMigrator` runs at boot via a Rails initializer, applies any pending migrations, stamps the new version, and writes a timestamped backup (`config.yaml.pre-migration-<UTC>.bak`) before any change. The backup is removed once the migration has succeeded; failures leave it behind so the original file can be recovered manually.
- `Configuration#save!` always writes the current `_schema_version` along with the data once at least one migration is registered, so newly created files start out properly stamped. A higher existing version is preserved (no silent downgrade).
- The migrator is skipped in the test environment; specs and fixtures already match the current schema. Fixtures are regenerated through `bin/rake fixtures:regenerate` whenever the schema advances.

Testing strategy mirrors Rails: the DSL on `ConfigurationMigrations::Base` is unit-tested thoroughly, individual migrations are not. The `ConfigurationMigrator` itself is tested with a stand-in migration so its behavior stays independent of which real migrations happen to be registered.

## Consequences

**Positive:**

- Schema evolutions can move, rename, or restructure fields without losing user data.
- Migrations stay short and declarative thanks to the DSL — adding one is roughly a dozen lines of intent, no boilerplate.
- The migration history lives in `app/services/configuration_migrations/` — easy to audit, easy to add to.
- `Configuration#sanitize_sections!` can stay strict; it no longer needs to tolerate stale fields, because migrations remove them deliberately.
- A timestamped backup before each run is a cheap safety net for the rare case a migration ships with a bug — removed automatically on success, retained on failure.

**Negative:**

- One more thing to maintain: every schema change adds a migration class.
- Down-migrations are not supported; a downgrade after a migration ran is a manual restore from the backup.
- Test fixtures must be regenerated after each schema change so they include the new `_schema_version` stamp (the existing `bin/rake fixtures:regenerate` task does this automatically).
- Extending the DSL with new operations (e.g. `rename_section`, `delete_field`) requires adding both the helper and matching tests on the base class.
