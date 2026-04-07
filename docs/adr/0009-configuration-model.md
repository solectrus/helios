# ADR-0009: Configuration Model

## Status

Accepted (updated to reflect file-based YAML implementation)

## Context

Helios needs to store user configuration that drives the generation of `compose.yaml` and `.env` files. This includes:

- General settings (timezone, installation date)
- Device/service configuration (inverter, wallbox, heatpump, etc.)
- Sensor mappings

Options considered:

1. Key-value settings table
2. Typed models per configuration area
3. Database with JSON blobs
4. **File-based YAML** (chosen)

## Decision

Use a single `config.yaml` file to store all configuration. The `Configuration` model reads and writes this file directly — no database tables are needed.

Configuration is organized into named singletons (chapters), each representing a specific area:

```ruby
# Usage
config = Configuration.current
config.system
# => { "installation_date" => "2024-01-15", "timezone" => "Europe/Berlin" }

config.update('system', { 'installation_date' => '2024-01-15', 'timezone' => 'Europe/Berlin' })
```

## Singletons

Defined in `Configuration::SINGLETONS`:

| Singleton  | Purpose                     |
| ---------- | --------------------------- |
| `system`   | Installation date, timezone |
| `devices`  | Device configuration        |
| `inverter` | Inverter settings           |
| `wallbox`  | EV charger settings         |
| `heatpump` | Heat pump settings          |
| `mqtt`     | MQTT configuration          |
| `forecast` | Weather forecast settings   |

## Consequences

**Positive:**

- No database needed — simpler architecture, no migrations
- Each singleton is independently editable
- Flexible schema, easy to extend
- Singletons can be completed incrementally (setup wizard)
- YAML is human-readable and easy to debug
- File can be backed up/restored trivially

**Negative:**

- No database-level validation (must validate in Ruby)
- Concurrent writes require care (acceptable for single-user admin tool)

## Data Flow

```
User Input (UI) → config.yaml → StackBuilder → compose.yaml + .env
```

`StackBuilder` reads the YAML configuration and generates both `compose.yaml` and `.env`.
