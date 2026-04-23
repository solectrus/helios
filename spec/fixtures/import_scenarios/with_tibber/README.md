# with_tibber

Minimal stack extended with a `tibber-collector` service. Like `with_senec_charger`,
it tests the unmanaged-service preservation path, but for a collector with no
associated sensors.

## Highlights

- **`tibber-collector` is not a known HELIOS service** → imported under
  `_unmanaged.services.tibber-collector` with image, environment, env_values
  (`TIBBER_TOKEN`, `TIBBER_INTERVAL`, `INFLUX_MEASUREMENT_TIBBER`), `depends_on`
  and `restart`.
- **`sensors: {}`** — no sensors at all. The stack has no dashboard-side
  `INFLUX_SENSOR_*` mappings, so the top-level `sensors:` key stays empty
  rather than being omitted.
- **Only baseline services** (`dashboard`, `influxdb`, `postgresql`, `redis`,
  `watchtower`) plus the Tibber collector — no SENEC, Shelly, forecast or MQTT
  collector.
- Demonstrates that an unmanaged service's literal env values (like
  `INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_TIBBER}`) round-trip unchanged.
