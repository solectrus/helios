# ADR-0009: Configuration Model

## Status

Accepted (updated to reflect chapters-based implementation)

## Context

Helios needs to store user configuration that drives the generation of `compose.yaml` and `.env` files. This includes:

- General settings (timezone, installation date)
- Device/service configuration (inverter, wallbox, heatpump, etc.)
- Sensor mappings (Phase 2)

Options considered:

1. Key-value settings table
2. Typed models per configuration area
3. Single JSON blob
4. **Chapters-based model** (chosen)

## Decision

Use a `configurations` table with associated `chapters` records. Each chapter stores a JSON blob for a specific configuration area.

```ruby
# Schema
create_table :configurations do |t|
  t.json :data, null: false, default: {}
  t.timestamps
end

create_table :chapters do |t|
  t.references :configuration, null: false, foreign_key: true
  t.string :name, null: false
  t.json :data, null: false, default: {}
  t.timestamps
  t.index [:configuration_id, :name], unique: true
end

# Usage
config = Configuration.current
config.chapter('system')
# => { "installation_date" => "2024-01-15", "timezone" => "Europe/Berlin" }

config.update_chapter('system', { 'installation_date' => '2024-01-15', 'timezone' => 'Europe/Berlin' })
```

## Chapter Names

Defined in `Chapter::NAMES`:

| Chapter    | Purpose                       |
| ---------- | ----------------------------- |
| `system`   | Installation date, timezone   |
| `devices`  | Device configuration          |
| `inverter` | Inverter settings             |
| `wallbox`  | EV charger settings           |
| `heatpump` | Heat pump settings            |
| `mqtt`     | MQTT configuration            |
| `forecast` | Weather forecast settings     |

## Consequences

**Positive:**

- Each chapter is independently editable
- Flexible JSON schema per chapter, easy to extend
- No migrations needed for new config options
- Chapters can be completed incrementally (setup wizard)
- Single `Configuration` record tracks global state (e.g., `setup_completed`)

**Negative:**

- No database-level validation of JSON content (must validate in Ruby)
- Queries on nested fields are less efficient (acceptable for single-row config)

## Data Flow

```
User Input (UI) → Configuration + Chapters (SQLite/JSON) → StackBuilder → compose.yaml + .env
```

`StackBuilder` reads configuration and chapters, then generates both `compose.yaml` and `.env`.
