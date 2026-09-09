# with_ingest_external

The `with_ingest` stack with one change: the MQTT mapping for the balcony
inverter is gone. `Garage:inverter_power` therefore arrives from a source that
HELIOS does not manage.

## Highlights

- **Balcony power plant from an external source.** `inverter_power_2` keeps
  `is_balcony: true` but imports as `source: external`, because no collector in
  the stack writes `Garage:inverter_power`.
- **Ingest stays in the export.** The balcony flag alone decides
  (`Configuration#ingest_required?`). The external source has to write to
  Ingest instead of InfluxDB, and HELIOS names that address on the sensor list
  and in the Ingest settings.
- **The external sensor reaches Ingest as a variable.**
  `INFLUX_SENSOR_INVERTER_POWER_2` is part of the Ingest environment, so the
  house power calculation waits for that value.
- Everything else matches `with_ingest`, including the derived `SENEC_IGNORE`
  and the preserved `INFLUX_MEASUREMENT_TIBBER` under `_unmanaged.env_vars`.
