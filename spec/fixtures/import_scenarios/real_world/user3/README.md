# user3

Real-world `docker-compose.yml` + `.env` from a SOLECTRUS user with a SENEC
battery, a small balcony plant feeding through Ingest, four Shelly devices,
sixteen MQTT mappings, and a multi-plane pvnode forecast. Anonymized but
otherwise untouched.

## Highlights

- **Legacy compose filename `docker-compose.yml`** — the user runs the
  pre-Compose-Spec filename, so the importer must resolve `Compose::FILENAMES`
  in lazy order and accept the `.yml` variant alongside `compose.yaml`.
- **One shelly-collector service per device** — the source compose declares
  four separate services (`shelly-collector-terrasse`, `-aufzug`, `-therme`,
  `-herd`), each parameterized by `SHELLY_HOST_X` / `SHELLY_MEASUREMENT_X`.
  The importer matches them by image and merges all four into a single
  managed `shelly-collector` with comma-joined `SHELLY_HOST` and
  `INFLUX_MEASUREMENT` lists.
- **3-phase Shelly feeding two sensors** — the TERRASSE Shelly is a Pro/Plus
  3EM that writes `power`, `power_a`, `power_b`, `power_c` into the same
  measurement. `INFLUX_SENSOR_CUSTOM_POWER_14=TERRASSE:power_a` (Phase A)
  becomes a managed shelly sensor; `INFLUX_SENSOR_INVERTER_POWER_2=TERRASSE:power_c`
  (Phase C, balcony inverter) keeps `senec` source via `SENEC_DEFAULTS` but
  carries the explicit measurement+field override. Both round-trip through
  the same shelly-collector-terrasse instance.
- **Balcony plant auto-detected** — `INFLUX_SENSOR_INVERTER_POWER_2=TERRASSE:power_c`
  uses a different measurement than the main SENEC inverter
  (`INFLUX_SENSOR_INVERTER_POWER_1=SENEC:inverter_power`), so
  `mark_balcony_sensor!` flags `inverter_power_2` with `is_balcony: true`
  even though the user never set the flag explicitly.
- **`SHELLY_MEASUREMENT_*` aliases recognized as redundant** — the user
  defines `SHELLY_MEASUREMENT_AUFZUG=AUFZUG` etc. and references them via
  `${SHELLY_MEASUREMENT_X}` in each per-device shelly-collector. After
  HELIOS rewrites the collector to use a CSV `INFLUX_MEASUREMENT` list,
  the aliases are dead weight; `redundant_measurement_alias?` covers both
  `INFLUX_MEASUREMENT_*` and `SHELLY_MEASUREMENT_*` so they don't leak
  into `_unmanaged.env_vars`.
- **Custom Watchtower image `nickfedor/watchtower`** — preserved as
  `nickfedor/watchtower:latest` (same forked Watchtower as user1).
- **Cron-style `command: --scope solectrus --cleanup --schedule "0 0 8,20 * * *"`** —
  the user runs Watchtower on a fixed cron instead of polling. HELIOS
  rewrites the service to use `WATCHTOWER_POLL_INTERVAL=86400` (default);
  the schedule is intentionally lost on re-export.
- **Twelve empty `INFLUX_SENSOR_*=` entries** — `INVERTER_POWER`,
  `INVERTER_POWER_3..5`, `HEATPUMP_HEATING_POWER`, `HEATPUMP_STATUS`,
  `HEATPUMP_TANK_TEMP`, `OUTDOOR_TEMP`, `WALLBOX_POWER`,
  `EXCLUDE_FROM_HOUSE_POWER` are all blank and dropped (no sensor
  registered) instead of being re-exported as empty mappings.
- **Split read/write tokens collapsed** — the source uses
  `INFLUX_TOKEN_READ` / `INFLUX_TOKEN_WRITE` everywhere (Dashboard reads,
  collectors write). Re-export consolidates to a single `INFLUX_TOKEN`,
  matching HELIOS's canonical scheme.
- **Duplicate Influx env vars in `.env`** — `INFLUX_HOST`, `INFLUX_PORT`,
  `INFLUX_SCHEMA`, `INFLUX_ORG`, `INFLUX_TOKEN` are defined twice (once in
  the MQTT block, once in the InfluxDB block). The importer tolerates the
  redefinitions; only the canonical names survive on re-export.
- **`PVNODE_PAID=TRUE` uppercase** — preserved verbatim under
  `forecast.forecast_pvnode_paid: 'TRUE'` instead of being normalized to
  lowercase. The forecast-collector accepts either form.
- **`POWER_SPLITTER_INTERVAL=300`** — re-emitted in `.env` as a HELIOS
  default with name-only passthrough in the power-splitter service.
  Donor value matches HELIOS's hardcoded default.
- **Mid-block German comments and blank lines in the dashboard
  `environment:` array** — `# Benutzer definierte Verbraucher`,
  `# Extra Sensoren PV Node` separate logical groups inside the YAML
  list. Comments are dropped on re-export (acceptable per CLAUDE.md);
  the importer must not choke on the structure.
- **Indentation typos in `logging:` blocks** — `shelly-collector-therme`
  and `shelly-collector-herd` indent `options:` with 5 spaces instead of 6.
  Compose still parses it (the indent is consistent within the block);
  the importer must follow suit.
- **Trailing tabs/spaces on env list items** —
  `INFLUX_SENSOR_CUSTOM_POWER_14\t` (dashboard) and `_10\t` (power-splitter)
  end with a tab; the file ends on a stray-space line. YAML round-trips
  these without complaint.
- **Variable indirection `INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_FORECAST}`** —
  the forecast-collector references the measurement via an intermediate
  env var rather than inline. The importer must dereference to
  `forecast.measurement: forecast`.
- **Orphan MQTT mapping `MAPPING_15`** — points at a Weather-Station
  outdoor-temperature topic (`ws2900_v2_01_18_outdoor_temperature:temperature`),
  but `INFLUX_SENSOR_OUTDOOR_TEMP=` is empty so no HELIOS sensor consumes
  the mapping. Preserved under `mqtt.mappings:` and re-emitted as the
  trailing `(additional)` entry so the user's mqtt-collector keeps writing the
  topic into InfluxDB after import. Editable via the MQTT settings UI.
- **Sixteen MQTT mappings, mixed JSON-key vs. flat payloads** — mappings
  0–9 (zigbee2mqtt) carry `MAPPING_N_JSON_KEY=power`, while mappings
  10–15 (homeassistant scalar topics) deliberately omit `_JSON_KEY`.
  Both styles round-trip 1:1.
- **`dozzle` log viewer** — unrecognized service preserved verbatim under
  `_unmanaged.services.dozzle` with its socket mount and port mapping.
