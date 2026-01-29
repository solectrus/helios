# ADR-0009: Configuration Model

## Status

Accepted

## Context

Helios needs to store user configuration that drives the generation of `compose.yaml` and `.env` files. This includes:

- General settings (timezone, installation date)
- Sensor mappings (InfluxDB measurement/field combinations)
- Service enablement (which optional services are active)

Options considered:

1. Key-value settings table
2. Typed models per configuration area
3. Single JSON blob

## Decision

Use a single JSON blob stored in a `configurations` table.

```ruby
# Schema
create_table :configurations do |t|
  t.json :data, null: false, default: {}
  t.timestamps
end

# Usage
config = Configuration.current
config.data['general']['timezone']
config.data['sensors']['grid_import_power']['measurement']
```

## JSON Structure

```json
{
  "general": {
    "installation_date": "2024-01-15",
    "timezone": "Europe/Berlin"
  },
  "sensors": {
    "grid_import_power": {
      "measurement": "grid",
      "field": "import_power"
    },
    "house_power": {
      "measurement": "house",
      "field": "power"
    },
    "battery_soc": {
      "measurement": "battery",
      "field": "soc"
    }
  },
  "services": {
    "dashboard": {
      "enabled": true,
      "port": 3000
    },
    "power_splitter": {
      "enabled": true
    },
    "forecast_collector": {
      "enabled": false
    }
  }
}
```

## Consequences

**Positive:**

- Flexible schema, easy to extend
- Single source of truth for all configuration
- Easy to export/import (JSON serialization)
- No migrations needed for new config options
- Hierarchical structure matches domain model

**Negative:**

- No database-level validation (must validate in Ruby)
- No foreign key constraints
- Queries on nested fields are less efficient (acceptable for single-row config)

## Data Flow

```
User Input (UI) → Configuration (SQLite/JSON) → Generators → compose.yaml + .env
```

**Generators:**

- `ComposeGenerator` reads configuration, produces `compose.yaml`
- `EnvGenerator` reads configuration, produces `.env`

Both generators are triggered when configuration changes. The generated files are the "compiled output" of the configuration.
