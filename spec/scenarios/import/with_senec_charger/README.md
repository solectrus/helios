# with_senec_charger

Stack with the **managed** `senec-charger` service (Phase 2b): price-optimized
grid charging of a local SENEC battery. Verifies that HELIOS adopts the charger
as a first-class service when all its dependencies are present.

## Highlights

- **`senec-charger` is a managed HELIOS service** → imported into a typed
  `senec_charger:` config section (the `CHARGER_*` tuning knobs), not
  `_unmanaged.services`. Re-exported with the canonical managed shape
  (watchtower scope label, json-file logging, read-only InfluxDB token).
- **Adoption preconditions met**: a `tibber-collector` (writes the prices the
  charger reads), a `forecast-collector` (writes the forecast it reads) and a
  locally-queried SENEC battery (the device it steers). The charger is always a
  managed service, never `_unmanaged`; without all three preconditions it is an
  invalid combination and is dropped rather than reproduced.
- **Read-only InfluxDB access**: the charger only queries prices and forecast,
  so it binds `INFLUX_TOKEN=${INFLUX_TOKEN_READ}`. The prices/forecast
  measurements are referenced via `${INFLUX_MEASUREMENT_PRICES}` /
  `${INFLUX_MEASUREMENT_FORECAST}`, emitted by the tibber/forecast sections.
- **`CHARGER_*` round-trip**: `CHARGER_INTERVAL`, `CHARGER_PRICE_MAX`,
  `CHARGER_PRICE_TIME_RANGE`, `CHARGER_FORECAST_THRESHOLD`, `CHARGER_DRY_RUN`
  are extracted into `senec_charger:` and re-emitted in the `.env`.
- **Dynamic Tibber prices** written to the `Tibber` measurement. Charger and
  collector are configured by a single survey, which routes the credentials
  into the `tibber:` section (`Configuration::BORROWED_FIELDS`).
- **Deprecated `INFLUX_SENSOR_*` values on the dashboard** — the legacy
  inline-mapping style is still mapped correctly to `source: senec` /
  `source: forecast` sensors.
- **Forecast collector with forecast.solar**, minimal config (no horizon,
  damping or API key).
