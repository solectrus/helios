# no_sensor_configuration

A real-world Synology-hosted setup that **does not use the modern
`INFLUX_SENSOR_*` mapping scheme** for most sensors. The importer has to
reconstruct the sensor map from other signals (MQTT topics and external-source
fallbacks).

## Highlights

- **Only one `INFLUX_SENSOR_*` variable defined** in `.env`
  (`INFLUX_SENSOR_HEATPUMP_POWER`). Every other sensor is inferred from:
  - MQTT legacy topic variables (`MQTT_TOPIC_HOUSE_POW`, `MQTT_TOPIC_GRID_POW`,
    `MQTT_TOPIC_BAT_FUEL_CHARGE`, `MQTT_TOPIC_BAT_POWER`,
    `MQTT_TOPIC_INVERTER_POWER`, `MQTT_TOPIC_WALLBOX_CHARGE_POWER`).
  - The `INFLUX_MEASUREMENT_PV=klushygel-pv-messung` bucket, used as
    `measurement` for `source: external` sensors.
- **`MQTT_FLIP_BAT_POWER=true`** → imported as `mqtt_formula` splitting the
  battery power topic into charging / discharging via
  `IF({value} < 0, -{value}, 0)` / `IF({value} > 0, {value}, 0)`.
- **Non-standard bucket name** `klushygel-pv` and measurement
  `klushygel-pv-messung`.
- **Synology volume paths** (`/volume1/docker/solectrus/{postgresql,influxdb,redis}`)
  become `volume_path` entries under `postgresql`, `influxdb`, `redis`.
- **`FRAME_ANCESTORS` with a URL value** (`https://192.168.178.10:8123`) —
  tests quoted-string handling in `.env`.
- No Shelly collector in `compose.yaml`, despite `SHELLY_HOST` being set —
  `shelly:` block is imported but no device list.
- **`INFLUX_EXCLUDE_FROM_HOUSE_POWER=HEATPUMP_POWER`** carried through to
  `heatpump_power.exclude_from_house_power: true` even though the heat pump
  is `source: external`.
