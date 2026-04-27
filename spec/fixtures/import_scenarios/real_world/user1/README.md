# user1

Real-world `compose.yaml` + `.env` from a long-running SOLECTRUS user,
anonymized but otherwise untouched. Lots of commented-out alternatives,
typos, and inline literals — exercises the importer's resilience.

## Highlights

- **Legacy service name `app`** — the source compose calls the SOLECTRUS
  Dashboard `app:` (its name in the original hosting guide), not the canonical
  `dashboard:`. The importer must alias it via `SERVICE_IMAGE_PREFIXES` and
  re-export under the new name.
- **Inline `WATCHTOWER_POLL_INTERVAL=28800`** — set on the watchtower service's
  `environment:` block (not in `.env`, not in `command:`). The importer must
  pick it up from the resolved service env to avoid silently overwriting the
  user's choice with the HELIOS default.
- **Custom Watchtower image `nickfedor/watchtower`** — preserved as
  `nickfedor/watchtower:latest` (explicit tag) instead of falling back to the
  HELIOS default image.
- **Inconsistent measurement names** — `INFLUX_SENSOR_INVERTER_POWER` uses
  `my-pv-measurement` (with hyphen), but `INVERTER_POWER_1..4` use
  `my_pv_measurement` (underscore). Both forms must round-trip 1:1; rewriting
  them would lose access to historical InfluxDB data.
- **Empty `INFLUX_SENSOR_INVERTER_POWER_5=`** — must be dropped, not
  exported as an empty mapping.
- **Orphan MQTT mappings** — `MAPPING_5/6/7` push `mpp1/2/3_power` into
  `my-pv-measurement`, but no HELIOS sensor matches. They are intentionally
  dropped (data isn't displayed by the dashboard either; bringing them back
  later requires a managed sensor).
- **`MQTT_TOPIC_BAT_VOLTAGE=evcc/site/homePower`** — legacy MQTT-collector
  variable HELIOS no longer manages, preserved as `_unmanaged.env_vars` so the
  user's (intentional or accidental) value is not lost.
- **Duplicate `FORECAST_INFLUX_MEASUREMENT=forecast`** — redundant with the
  canonical `INFLUX_MEASUREMENT_FORECAST`, kept as unmanaged for safety.
- **Auto-default sensors** — `INFLUX_MEASUREMENT_PV=my-pv-measurement` triggers
  `LegacySensorAdapter` to synthesize `case_temp`, `system_status`,
  `system_status_ok`, and `grid_export_limit` even though the user never set
  them explicitly.
- **Shelly collector dropped** — the user's compose declares a shelly-collector
  service, but `SHELLY_HOST` and `SHELLY_INTERVAL` are commented out in `.env`,
  so the service was inactive and is correctly omitted on re-export.
