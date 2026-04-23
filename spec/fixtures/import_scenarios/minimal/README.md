# minimal

Special case: **no `config.yaml`**, so this fixture is *not* part of the
round-trip suite in `spec/services/scenarios_spec.rb`. It is used only by the
low-level parser specs:

- `spec/services/compose/file_spec.rb` loads `compose.yaml.bak`.
- `spec/services/env/file_spec.rb` loads `.env.bak`.

## Highlights

- **Minimal compose file** with just `helios`, `postgresql` and `redis` — enough
  to exercise YAML parsing without dragging in every SOLECTRUS service.
- **`.env` acts as a comment/formatting torture test**:
  - Full-line comments (`# This is a full line comment`).
  - Inline comments (`API_KEY=secret123 # inline comment`).
  - Empty value (`EMPTY_VALUE=`).
  - Section headers (`# Section: Secrets`).
  - Multiple comment styles in sequence.
- Deliberately generic variable names (`DATABASE_URL`, `REDIS_URL`, `API_KEY`, …)
  to decouple parser logic from SOLECTRUS domain mapping.
