# multi_shelly

SENEC.Home 4 (cloud adapter) combined with **multiple individual Shelly collector
services** (one container per device), plus a Traefik reverse proxy.

## Highlights

- **SENEC cloud adapter** (`adapter: cloud`, `version: v4`) with
  `SENEC_USERNAME` / `SENEC_PASSWORD` and `SENEC_REQUEST_MODE=full`.
- **Per-device Shelly containers** `shelly-collector-fridge`,
  `shelly-collector-dishwasher`, `shelly-collector-washer` — each with its own
  `SHELLY_DEVICE_ID_*`, `SHELLY_INTERVAL` (20/22/23 s) and
  `INFLUX_MEASUREMENT_SHELLY_*`. Imported as three separate `custom_power_*`
  sensors rather than a combined Shelly collector.
- **Shelly cloud connection**: `SHELLY_CLOUD_SERVER`, `SHELLY_AUTH_KEY`,
  `connection: cloud`.
- **Forecast with 4 planes** using `forecast.solar` numbered variables
  (`FORECAST_0_*` … `FORECAST_3_*`), also pvnode as provider with
  `PVNODE_PAID=true` and `PVNODE_EXTRA_PARAMS`.
- **Empty sensor lines** (`INFLUX_SENSOR_HEATPUMP_POWER=`,
  `INFLUX_SENSOR_CAR_BATTERY_SOC=`) must be ignored.
- **Traefik** service is present in `compose.yaml` but no `APP_DOMAIN`/TLS config
  via Traefik labels — treated implicitly.
- `UI_THEME` and `CO2_EMISSION_FACTOR` intentionally commented out in `.env`.
