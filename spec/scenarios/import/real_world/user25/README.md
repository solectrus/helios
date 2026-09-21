# user25

Real-world `docker-compose.yml.bak` + `.env.bak` from a SOLECTRUS user
running a full **SENEC home stack**: a local `senec-collector`
(adapter `local`, v3, https) feeding inverter, grid, battery, wallbox
and `case_temp` sensors, alongside **seven per-device
`shelly-collector-*` services** (`-mw`, `-airfry`, `-gsa`, `-it`,
`-server`, `-fence`, `-fence2`) — one container per Shelly plug. A
`forecast-collector` (forecast.solar, single plane) and a
`power-splitter` round out the managed services. Anonymized (tokens,
passwords, secret key) and the forecast coordinates blunted to one
decimal; otherwise untouched, including the donor's typo-laden setup.

The fixture exercises a couple of import paths together that no single
prior fixture combines:

- **Two Shellys wired as separate balcony PV inverters.** `Fence:power`
  and `Fence2:power` map to `INFLUX_SENSOR_INVERTER_POWER_2/3`, so the
  importer stores them as `source: shelly` *inverter* sensors (not
  consumers). Each feeds a measurement distinct from the main SENEC
  inverter (and from each other), so the balcony detector flags **both**
  `inverter_power_2` and `inverter_power_3` `is_balcony: true` — two
  independent fence-mounted plants, not MPPT strings of one inverter.
  That is why HELIOS keeps the `ingest` service (balcony PV needs the
  house-power correction).
- **The donor mis-wired the Shelly data path** — and HELIOS fixes it
  on adoption. In the `.bak`, every `shelly-collector-*` writes with
  `INFLUX_HOST=influxdb`, i.e. **straight into InfluxDB, bypassing
  `ingest`**; only `senec-collector` and `mqtt-collector` go through
  the proxy. But two of those Shellys *are* PV inverters
  (`Fence`/`Fence2`), so their generation never reaches the ingest
  house-power correction and the donor's `HOUSE_POWER_CALCULATED` is
  wrong. On import HELIOS recognizes them as inverter sources behind a
  balcony sensor and re-exports the canonical `shelly-collector` with
  `INFLUX_HOST=ingest`, routing all Shelly data through the proxy and
  silently repairing the bypass. This `.bak` → export round-trip is the
  regression guard for that correction.
- **Five more Shellys as consumers** feed
  `INFLUX_SENSOR_CUSTOM_POWER_01..05`, each folded onto its
  `custom_power_*` sensor (host + measurement), leaving **no**
  standalone `shelly.devices` entry.
- **The donor's `mqtt-collector` is dead weight, so HELIOS drops it.**
  The service exists in the `.bak`, but `MQTT_HOST` is blank and its
  lone mapping is a placeholder (`foo/bar/baz` → `test:test`); no sensor
  draws from `source: mqtt`. HELIOS captures the section into
  `config.yaml` (`mqtt.mqtt_host: ''`, placeholder mapping intact) but,
  because the required `mqtt_host` field is empty, treats the source as
  incomplete and omits `mqtt-collector` from the exported
  `compose.yaml`. The useless collector round-trips as inert config, not
  as a running container.
- **Both `tibber-collector` and `senec-charger`** survive verbatim
  under `_unmanaged.services` (with their `env_values`), the expected
  Phase-2 gate behaviour: HELIOS does not yet model the
  Tibber-price-driven battery charging, so it round-trips it untouched.
