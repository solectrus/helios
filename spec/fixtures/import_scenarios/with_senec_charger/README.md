# with_senec_charger

Stack that includes the optional `senec-charger` service — which HELIOS does
**not** manage natively. Verifies the "unmanaged preservation" path for
SOLECTRUS-adjacent services.

## Highlights

- **`senec-charger` is not a known HELIOS service** → imported under
  `_unmanaged.services.senec-charger` as a full Compose definition (image,
  environment, env_values, depends_on, restart).
- The charger's scalar values (`CHARGER_DRY_RUN`, `CHARGER_FORECAST_THRESHOLD`,
  `CHARGER_INTERVAL`, `CHARGER_PRICE_MAX`, `CHARGER_PRICE_TIME_RANGE`) are
  captured in `env_values`, while variable-only references (`TZ`,
  `INFLUX_BUCKET`, …) stay in the `environment` list.
- **Mixed env syntax preserved**: lines without `=` are captured as
  variable references; lines with `=${…}` and literal values
  (`INFLUX_MEASUREMENT_PRICES=Tibber`) are preserved verbatim.
- **Deprecated `INFLUX_SENSOR_*` values on the dashboard** — the legacy
  inline-mapping style is still mapped correctly to `source: senec` /
  `source: forecast` sensors.
- **Forecast collector with forecast.solar**, minimal config (no horizon,
  damping or API key).
- No Shelly, MQTT or watchtower scope labels.
