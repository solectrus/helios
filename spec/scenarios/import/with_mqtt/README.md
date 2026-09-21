# with_mqtt

SENEC local combined with an MQTT collector pulling data from a go-eCharger
wallbox, a Tesla car and an espaltherma heat pump. Exercises all three MQTT
mapping styles.

## Highlights

- **Sparse / non-contiguous `MAPPING_*` indices** in `.env` — indices 0, 1, 5,
  6, 9, 23, 30 are used; the importer must not assume a dense sequence.
- **All three MQTT mapping styles covered**:
  - Plain `MAPPING_x_FIELD` without a json key (go-eCharger).
  - `MAPPING_x_JSON_KEY` for nested JSON (`DHW tank temp. (R5T)`, Tesla `soc`).
  - `MAPPING_x_JSON_FORMULA` for computed fields
    (heat pump `heat` and `current_state`).
- **MQTT without SSL/port in the config output** — `mqtt_ssl` is absent from
  the imported `mqtt:` block (distinguishes it from `with_ingest`, where empty
  credentials are written).
- **`INFLUX_EXCLUDE_FROM_HOUSE_POWER=WALLBOX_POWER`** applied to the
  wallbox sensor (not heatpump, unlike most scenarios).
- **`CO2_EMISSION_FACTOR=401`** left explicit in config even though it is the
  default, because it was set explicitly in `.env`.
