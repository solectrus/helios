# user23

Real-world `compose.yaml` + `.env` from a SOLECTRUS user running a
**cloud-adapter SENEC** (`SENEC_ADAPTER=cloud`, `SENEC_REQUEST_MODE=full`)
with **seventeen per-device cloud-mode `shelly-collector-*` services** for
whole-house appliance metering, a four-plane **pvnode** forecast, the official
**power-splitter**, and a **`nickfedor/watchtower`** fork. Anonymized but
otherwise untouched.

This snapshot is the **real-world, scaled-up counterpart of the synthetic
[`multi_shelly`](../../multi_shelly/) scenario**: same cloud-mode
per-device-services Shelly topology, same divergent per-service
`SHELLY_INTERVAL` collapse, same pvnode-with-four-planes forecast, same
empty-sensor-line handling — but at 17 devices instead of 3, straight from a
production stack. It exists as a stress test of that already-covered import
path against a real donor (largest Shelly fan-out in the corpus), not because
it exercises a brand-new importer quirk. The two genuinely real-world-only
wrinkles are called out under "Differences from `multi_shelly`" below.

## Already covered by `multi_shelly` (re-verified here at scale)

- **Seventeen per-device cloud-mode `shelly-collector-*` services →
  one CSV collector.** One container per appliance (`-fridge`, `-dishwasher`,
  `-washer`, `-oven`, `-dryer`, `-hob`, `-sauna`, `-pump22`, `-pump17`,
  `-heating_wc`, `-outdoor`, `-tv-bose`, `-froster`, `-trotec`, `-office`,
  `-lighting`, `-utility`), each with a single
  `SHELLY_DEVICE_ID=${SHELLY_DEVICE_ID_<NAME>}`. `ShellyExtractor#multi_device?`
  flattens all seventeen into one canonical `shelly-collector` with
  comma-separated `SHELLY_DEVICE_ID` / `INFLUX_MEASUREMENT`, and surfaces the
  device list as `shelly.devices` (alphabetized by `name`). `SHELLY_CLOUD_SERVER`
  + `SHELLY_AUTH_KEY` flip `raw_devices_context` onto the `device_id` field, and
  the per-device `name:` is recovered from the `${SHELLY_DEVICE_ID_<NAME>}`
  interpolation reference (via `shelly_interpolated_names`), not the sequential
  `deviceN` fallback. Same path as `multi_shelly`; the local-mode `SHELLY_HOST`
  variant of the same consolidation lives in
  [user18](../user18/README.md) and friends.

- **Divergent per-service `SHELLY_INTERVAL` → `min_interval` keeps the
  shortest.** Fourteen services pin `SHELLY_INTERVAL=20` inline; the three
  outliers `-office` / `-lighting` / `-utility` carry `21` / `22` / `23`; and
  the global `.env` sets `SHELLY_INTERVAL=5`. Shelly exposes a single UI field
  for the polling interval, so `ShellyExtractor#min_interval` collapses the
  per-service values to the shortest — `20`. The global `.env=5` never enters
  the calculation because each service's inline `SHELLY_INTERVAL=…` shadows it
  through `service_env`. Same collapse `multi_shelly` exercises with `20/22/23`.

- **SENEC cloud adapter** (`adapter: cloud`, `version: v4`,
  `SENEC_REQUEST_MODE=full`) — as in `multi_shelly`.

- **Four-plane pvnode forecast.** `FORECAST_PROVIDER=pvnode`,
  `FORECAST_CONFIGURATIONS=4`, `PVNODE_PAID=true`,
  `PVNODE_EXTRA_PARAMS=diffuse_radiation_model=perez`. The four roofs
  (`FORECAST_0..3_*`) import as `forecast_declination1..4` /
  `forecast_pvnode_azimuth1..4` / `forecast_kwp1..4` with `forecast_roofs: 4`.
  Same provider path as `multi_shelly` (and
  [user12](../user12/README.md) / [user15](../user15/README.md) /
  [user16](../user16/README.md)).

- **Empty sensor lines ignored.** `INFLUX_SENSOR_HEATPUMP_POWER=` and
  `INFLUX_SENSOR_CAR_BATTERY_SOC=` are present-but-blank and dropped from
  `config.yaml.sensors` — exactly as in `multi_shelly`.

## Differences from `multi_shelly` (real-world only)

- **Seventeen `custom_power` sensors, every one Shelly-sourced.**
  `INFLUX_SENSOR_CUSTOM_POWER_01..17` map to the Shelly measurements
  (`Fridge`, `Dishwasher`, `Washer`, …) and are preserved in their original
  `01..17` slot order even though `shelly.devices` is alphabetized — the
  round-trip aligns sensors to devices by **measurement name**, not slot or
  device order, so the two orderings coexist at this scale without drift.

- **`CUSTOM_POWER_18/19/20` referenced-but-unset.** The `dashboard` and
  `power-splitter` `environment:` lists name
  `INFLUX_SENSOR_CUSTOM_POWER_18/19/20`, but `.env` never assigns them. This
  is a slightly different shape than the present-but-blank lines above
  (declared in compose, no `.env` entry at all rather than `KEY=`), and the
  importer treats it identically: no `measurement:field` mapping → no sensor.

- **`nickfedor/watchtower` fork from CLI flags.** Donor's `watchtower` has no
  tag, no env, and steers via `--scope solectrus --cleanup`. HELIOS
  canonicalizes the image to `nickfedor/watchtower:latest` (its own baseline
  repo) and re-emits `WATCHTOWER_POLL_INTERVAL=86400` / `WATCHTOWER_SCOPE=solectrus`
  / `WATCHTOWER_CLEANUP=true` from `WATCHTOWER_DEFAULTS` — the same
  flag-to-env normalization as [user22](../user22/README.md), there landing on
  the donor's `containrrr/watchtower` instead.
