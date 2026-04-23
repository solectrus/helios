# senec3

Typical SENEC.Home V3 installation with the **local** adapter and a minimal set
of add-ons — only the core stack plus the SENEC collector. No forecast, no
Shelly, no MQTT.

## Highlights

- **SENEC V3 local adapter** (`adapter: local`, `version: v3`, `schema: https`,
  `language: de`, interval 5 s).
- **Multi-string inverter**: `INFLUX_SENSOR_INVERTER_POWER_1/2/3` mapped to
  SENEC's `mpp1_power` / `mpp2_power` / `mpp3_power`. Slots 4 & 5 and all
  `custom_power_*` lines intentionally left **empty** — must be dropped, not
  carried over.
- **`CO2_EMISSION_FACTOR=500`** overrides the default of 401.
- **Wallbox and forecast sensors empty** (`INFLUX_SENSOR_WALLBOX_POWER=`,
  `INFLUX_SENSOR_INVERTER_POWER_FORECAST=` …) — the importer must skip them
  rather than emit empty entries.
- Only the baseline services in `compose.yaml`: `dashboard`, `influxdb`,
  `postgresql`, `redis`, `watchtower`, `senec-collector`.
