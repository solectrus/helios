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
- **`SENEC_IGNORE` auto-derived — the switched-vendor collision.**
  `wallbox_power` is now MQTT-sourced but still writes into SENEC's own
  `SENEC:wallbox_charge_power` (so history and live data stay in one
  measurement). HELIOS no longer stores the donor's `SENEC_IGNORE`; it
  recomputes the list on export and, finding exactly this overlap, emits
  `SENEC_IGNORE=wallbox_charge_power` to stop the senec-collector from
  fighting the MQTT writer. The other foreign sensors here
  (`inverter_power_2` → `Garage`, `wallbox_car_connected` → `Car_Opel`)
  write into different measurements, so they are *not* ignored.
- **`car_battery_soc`, `wallbox_car_connected`** from HomeAssistant MQTT topics.
- **Unknown env var `INFLUX_MEASUREMENT_TIBBER=my-tibber`** preserved under
  `_unmanaged.env_vars`.
