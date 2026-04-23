# with_ingest

Installation that ships the standalone `ingest` service (the HTTP ingest
front-end to InfluxDB), plus a mixed sensor setup combining SENEC, MQTT and a
secondary balcony inverter.

## Highlights

- **`ingest:` service** recognised as a first-class top-level `ingest:` block in
  `config.yaml` — not relegated to `_unmanaged`.
- **Balcony / second inverter via MQTT**: `inverter_power_2` with
  `is_balcony: true` and `mqtt_topic: homeassistant/PV/GaragePower`.
  `inverter_power_1` comes from SENEC.
- **Split InfluxDB tokens** (`INFLUX_TOKEN_READ` / `INFLUX_TOKEN_WRITE`) —
  collapsed by import.
- **1-0-beta dashboard tag** (`solectrus:1-0-beta`) preserved as-is.
- **Empty MQTT credentials** (`MQTT_PASSWORD=''`, `MQTT_USERNAME=''`) must be
  imported as empty strings, not stripped.
- **`SENEC_IGNORE=wallbox_charge_power`** + wallbox power instead sourced from
  MQTT (`homeassistant/lp/1/W`).
- **`car_battery_soc`, `wallbox_car_connected`** from HomeAssistant MQTT topics.
- **Unknown env var `INFLUX_MEASUREMENT_TIBBER=my-tibber`** preserved under
  `_unmanaged.env_vars`.
