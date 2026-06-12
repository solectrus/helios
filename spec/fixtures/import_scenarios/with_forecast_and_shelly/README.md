# with_forecast_and_shelly

SENEC local + a forecast.solar forecast collector + a Shelly collector with
mixed per-device passwords. Exercises comma-separated list-style collector
variables and the no-collision branch of auto-derived `SENEC_IGNORE`.

## Highlights

- **Inline environment values** — most sensor / host variables are hard-coded
  directly in `compose.yaml` (`INFLUX_SENSOR_*=SENEC:...`, `APP_HOST=myhost`),
  not referenced from `.env`. The importer has to merge both sources.
- **`forecast.solar`** provider with the full option set:
  `FORECAST_DAMPING_MORNING`, `FORECAST_DAMPING_EVENING`, `FORECAST_HORIZON=24`,
  `FORECAST_INVERTER=1`, `FORECAST_SOLAR_APIKEY`.
- **Shelly comma-list trickery**: `SHELLY_HOST=shelly-hp.local,shelly-wb.local,shelly-fridge.local`
  paired with `SHELLY_PASSWORD=,secret,` (blank / `secret` / blank) — tests
  index-aligned parsing of parallel lists.
- **`SENEC_IGNORE` not imported — auto-derived, and empty here.** HELIOS no
  longer stores the donor's `SENEC_IGNORE=wallbox_charge_power,grid_power_minus`;
  it recomputes the list on export, ignoring a SENEC field only when a
  foreign-sourced sensor reuses SENEC's own `measurement:field`. `wallbox_power`
  comes from Shelly but writes into measurement `Wallbox` (not `SENEC`), and
  `grid_export_power` imports as `source: senec` — neither overlaps the SENEC
  collector's output, so nothing is ignored.
- **`heatpump_power` via Shelly** (`source: shelly`, `shelly_host: shelly-hp.local`).
- Only one forecast plane (no numbered `FORECAST_0_*` variables).
