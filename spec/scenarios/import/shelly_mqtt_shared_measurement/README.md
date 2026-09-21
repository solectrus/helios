# Scenario: shelly_mqtt_shared_measurement

A Shelly device and an MQTT mapping write **different fields into the same
`heatpump` measurement**:

- `heatpump_power` → `heatpump:power` (Shelly, via `SHELLY_HOST` CSV)
- `heatpump_heating_power` → `heatpump:heating_power` (MQTT mapping)
- `custom_power_01` → `fridge:power` (second Shelly device)

SOLECTRUS allows multiple collectors to share a measurement. This is a
regression guard: `heatpump_power` must stay `source: shelly` and keep its
`shelly_host`, even though the MQTT sensor `heatpump_heating_power` also writes
the `heatpump` measurement. A naive "another collector writes this measurement
→ drop the Shelly" rule stripped `heatpump_power`'s host and (on re-import)
flipped the sensor to `source: external`.
