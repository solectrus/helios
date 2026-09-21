# with_external

Installation where every power/temperature sensor is sourced **externally**
(data is pushed into InfluxDB by some other process, not a SOLECTRUS collector).
HELIOS itself is already part of the stack.

## Highlights

- **`helios` service present** in `compose.yaml` — the stack is already
  HELIOS-managed.
- **`source: external` for nearly all sensors** (battery, grid, house, inverter
  1–3, wallbox, heatpump, outdoor, custom_power_01–04 …).
- **Forecast-only exceptions**: `inverter_power_forecast`,
  `inverter_power_forecast_clearsky`, `outdoor_temp_forecast` use
  `source: forecast` — but there is **no forecast collector** in compose; the
  config carries no top-level `forecast:` block.
- **No SENEC / Shelly / MQTT collectors at all** — dashboard relies purely on
  pre-existing InfluxDB data.
- **`INFLUX_EXCLUDE_FROM_HOUSE_POWER=HEATPUMP_POWER`** carried through to
  `heatpump_power.exclude_from_house_power: true` despite `source: external` —
  ensures the flag survives import for non-Shelly sensors too.
- **Custom volume paths** `/opt/solectrus/{postgresql,influxdb,redis}` (via
  `DB_VOLUME_PATH`, `INFLUX_VOLUME_PATH`, `REDIS_VOLUME_PATH`).
- Dashboard uses the `develop` tag (`solectrus:develop`).
- `POWER_SPLITTER_INTERVAL=300` — HELIOS pins this to a fixed `300`
  (5-minute cadence) for every stack, not configurable and not stored
  in `config.yaml`. Matches the donor value here, so the `.env` round-trips
  unchanged.
