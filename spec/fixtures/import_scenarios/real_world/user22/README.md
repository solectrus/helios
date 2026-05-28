# user22

Real-world `docker-compose.yml` + `.env` from a SOLECTRUS user with a SENEC
battery, a small balcony plant fed through a Shelly, six per-device
shelly-collector services for household-appliance metering, a single
MQTT mapping behind an empty broker, Tibber-based grid charging, and a
forecast.solar geometry with `SOLCAST_SITE` left over from a prior
provider trial. The donor pins a vintage `1-0-beta` tag on the legacy
`solectrus/solectrus` dashboard image, and ships the MQTT collector with
a literal YAML `...` placeholder where extra mappings would slot in.
Anonymized but otherwise untouched.

## Highlights

- **`docker-compose.yml.bak` filename, not `compose.yaml.bak`** — donor
  uses Docker Compose v1's historical filename, same variant as
  [user21](../user21/README.md). `Compose::FILENAMES` accepts every
  spelling and the round-trip spec resolves the same backup path via
  the lazy `FILENAMES.map` lookup.
- **Legacy `ghcr.io/solectrus/solectrus:1-0-beta` image** — donor pins
  the historical Dashboard repository (`solectrus/solectrus`, before
  the `dashboard` rename) at the `1-0-beta` release-candidate tag.
  Preserved verbatim through
  `SERVICE_IMAGE_PREFIXES['dashboard'] = %w[ghcr.io/solectrus/solectrus]`
  rather than auto-rewritten to `ghcr.io/solectrus/dashboard`, so the
  user keeps running the exact image+tag they already pull. Same
  preservation path as user21, but pinned to a specific release tag
  instead of `:latest`.
- **MQTT mapping `...` placeholder in compose env list** — donor's
  `mqtt-collector` declares twenty-plus `MAPPING_0_*` slots and then a
  literal `- ... # weitere Mappings bei Bedarf` line (German for
  "more mappings if needed"). YAML parses `...` as the plain string
  `"..."`; HELIOS' compose env extractor only keeps entries matching
  the POSIX env-var name pattern (`[A-Z_][A-Z0-9_]*`, optionally with
  `=value`), so the bare `...` token is silently discarded along with
  the unset `MAPPING_0_JSON_KEY` / `_JSON_PATH` / `_JSON_FORMULA` /
  `_MEASUREMENT_POSITIVE` / `_FIELD_POSITIVE` / `_MIN` / `_MAX`
  variants. The four populated slots (`TOPIC`, `MEASUREMENT`, `FIELD`,
  `TYPE`) are read into `config.yaml.mqtt.mappings`; the `mqtt-collector`
  service itself is then dropped on re-export because the broker host
  is blank (next bullet). First fixture exercising the `...`
  literal-as-env-entry shape.
- **Empty `MQTT_HOST=` paired with a fully configured `MAPPING_0` →
  `mqtt-collector` skipped on export, mapping retained in config** —
  donor sets `MQTT_HOST=`, `MQTT_USERNAME=`, `MQTT_PASSWORD=` (all
  empty) but `MAPPING_0_TOPIC=foo/bar/baz`, `MAPPING_0_MEASUREMENT=test`,
  `MAPPING_0_FIELD=test`, `MAPPING_0_TYPE=integer`. The donor was
  running an `mqtt-collector` container restart-looping against an
  empty broker; HELIOS refuses to reproduce that. The exported
  `compose.yaml` omits `mqtt-collector` entirely and the exported
  `.env` drops the `MQTT broker` section — `MQTT_HOST` / `MQTT_PORT` /
  `MQTT_SSL` / `MAPPING_0_*` are all gone — because
  `Services::MqttCollector.enabled?` now gates on
  `configuration.mqtt&.mqtt_host.present?` (the same single-point gate
  feeds `Env::SECTIONS`, so the env section is skipped automatically).
  The mapping survives in `config.yaml.mqtt.mappings` together with
  `mqtt_host: ''`, the HELIOS UI flags the MQTT settings section with
  the `incomplete` badge (via
  `Configuration#incomplete_sources` / `SOURCE_REQUIRED_FIELDS['mqtt']
  = 'mqtt_host'`), and the moment the user fills in a real broker
  host through the UI the collector and env section reappear on the
  next export. First fixture exercising the host-blank skip gate.
- **GSA Shelly: device-name vs measurement vs sensor-reference triangle
  is broken in the donor and HELIOS preserves the brokenness** — donor
  declares `SHELLY_HOST_GSA=192.168.2.51` and
  `INFLUX_MEASUREMENT_SHELLY_GSA=gas` (device is named "GSA", writes
  into the `gas` measurement), but the sensor mapping reads
  `INFLUX_SENSOR_CUSTOM_POWER_03=gsa:power` — pointing at a measurement
  literally called `gsa`, which nobody writes to. HELIOS keeps both
  halves intact: `shelly.devices` carries the working `{ name: gsa,
  measurement: gas, host: 192.168.2.51 }` pair, and the exported
  `INFLUX_MEASUREMENT` CSV lists `gas` in its slot; `custom_power_03`
  lands as `{ name: gsa, measurement: gsa, source: external }` —
  flagged as external because no managed source produces the `gsa`
  measurement that the donor's sensor expects. The donor's runtime
  reads an empty series on the dashboard while the Shelly happily
  writes to an orphaned `gas` measurement; HELIOS' policy is to
  preserve broken state verbatim rather than silently fix it, so the
  user can spot the typo in the HELIOS UI and reconcile it themselves.
  Compare the four sibling slots (`_01=airfry:power`, `_02=mw:power`,
  `_04=it:power`, `_05=server:power`) which all match their respective
  Shellies' measurements cleanly and resolve as `source: shelly`.
- **Fence Shelly serves two sensor roles simultaneously** — donor maps
  `INFLUX_SENSOR_INVERTER_POWER_2=Fence:power` (a Shelly metering a
  balcony PV string) alongside the SENEC main string at
  `INFLUX_SENSOR_INVERTER_POWER_1=SENEC:inverter_power`. The Shelly is
  also declared in `SHELLY_HOST_FENCE=192.168.2.55` /
  `INFLUX_MEASUREMENT_SHELLY_FENCE=Fence`, so the same physical device
  appears both in `shelly.devices` (as a regular metering target) and
  as the source of `inverter_power_2`. The measurement-divergence
  heuristic flips `is_balcony: true` on `inverter_power_2` because its
  `Fence` measurement differs from `inverter_power_1`'s `SENEC` — same
  auto-detection as user3's `TERRASSE:power_c`. Note the capitalized
  measurement name `Fence` (vs the lowercase `airfry` / `gas` / `it` /
  `mw` / `server` siblings) round-trips untouched in both the CSV
  `INFLUX_MEASUREMENT` and the per-sensor mapping.
- **Six per-device shelly-collector services collapse into one** —
  donor runs `shelly-collector-airfry`, `-mw`, `-gsa`, `-it`,
  `-server`, `-fence`, each pulling
  `image: ghcr.io/solectrus/shelly-collector:latest` and templating
  `SHELLY_HOST=${SHELLY_HOST_<NAME>}` /
  `INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_SHELLY_<NAME>}`. HELIOS'
  `ShellyExtractor` aggregates them into a single `shelly.devices`
  list (six entries, alphabetized by name) and exports one canonical
  `shelly-collector` reading CSV-valued `SHELLY_HOST` and
  `INFLUX_MEASUREMENT` (six comma-separated values each). Same
  collapse path as [user12](../user12/README.md) /
  [user18](../user18/README.md) — neither the device count nor the
  per-device name extraction is new — but this fixture is the first
  to combine the multi-device topology with a name↔measurement
  mismatch on one of the devices (the GSA case above), confirming
  the collapse doesn't silently align names with measurements when
  the donor's pairing diverges.
- **`SHELLY_HOST_IT=192.168.3.53` lives on a different subnet** — five
  Shellies sit in `192.168.2.x`, the IT-cabinet Shelly sits in
  `192.168.3.x`. HELIOS makes no inference from subnet boundaries; the
  IP round-trips into the CSV `SHELLY_HOST` list unchanged. Mentioned
  here only as a sanity check that the multi-device collapse doesn't
  introduce subnet-validation surprises.
- **Empty `INFLUX_SENSOR_INVERTER_POWER=` (slot 0) alongside populated
  `_1` / `_2`** — donor's legacy slot-0 spelling is explicitly empty,
  with `_1` and `_2` carrying the SENEC + Fence values. HELIOS skips
  the empty unindexed slot on import; the exported `compose.yaml` env
  blocks list only `INFLUX_SENSOR_INVERTER_POWER_1` and
  `INFLUX_SENSOR_INVERTER_POWER_2` (no `INFLUX_SENSOR_INVERTER_POWER`
  without index), matching the populated-slot-only export rule.
- **Five of eleven `INFLUX_SENSOR_CUSTOM_POWER_*` populated; compose
  env declares twenty slots** — `.env.bak` defines slots `_01..._11`
  with five values (`_01..._05`) and six empties, while the
  dashboard + power-splitter compose env blocks declare twenty slots
  (`_01..._20`). The donor over-scaffolded for future appliances;
  HELIOS exports only the five populated slots and drops slots
  `_06..._20` from both the env block and the `sensors:` map. Same
  drop policy as the empty inverter slot above.
- **`INFLUX_SENSOR_HOUSE_POWER_CALCULATED` declared on ingest's env
  but unset in `.env.bak`** — donor's compose lists
  `- INFLUX_SENSOR_HOUSE_POWER_CALCULATED` on the ingest service, but
  there is no `INFLUX_SENSOR_HOUSE_POWER_CALCULATED=` line in the
  `.env`. Compose passes it through as unset; HELIOS drops the slot
  from the exported ingest env block since there is no value to emit
  and no managed source produces it. Confirms HELIOS doesn't fabricate
  a placeholder for an env var the donor referenced but never set.
- **`SOLCAST_SITE=1111-2222-3333-4444` leftover from a forecast.solar
  install** — `FORECAST_PROVIDER=forecast.solar` is active and the
  forecast.solar geometry is fully configured (`FORECAST_LATITUDE` /
  `_LONGITUDE` / `_DECLINATION` / `_AZIMUTH` / `_KWP`), but
  `SOLCAST_SITE` carries a leftover value from a prior Solcast trial
  (or a copy-paste from a community recipe). HELIOS drops it on
  re-export because the active provider doesn't use it — same policy
  as [user14](../user14/README.md). The forecast geometry survives
  intact under `forecast.forecast_*1` keys.
- **`senec-charger` and `tibber-collector` preserved as
  `_unmanaged`** — donor runs both: tibber-collector polls Tibber
  prices into `INFLUX_MEASUREMENT_PRICES=tibber`, and senec-charger
  reads those plus the forecast to decide when to force-charge the
  SENEC battery from grid (`CHARGER_PRICE_MAX=85`,
  `CHARGER_FORECAST_THRESHOLD=20`, `CHARGER_DRY_RUN=false`,
  `CHARGER_INTERVAL=3600`). HELIOS has no first-class form for either
  service (issue #89 Phase 2), so both lift verbatim into
  `_unmanaged.services` with their full `environment` / `depends_on` /
  `links` / `logging` blocks preserved, and re-emit at the end of
  `compose.yaml` under the "Unmanaged service" banner. The associated
  `.env` vars (`TIBBER_TOKEN`, `TIBBER_INTERVAL`, `INFLUX_MEASUREMENT_PRICES`,
  `CHARGER_*`) land in their own `tibber-collector — service environment`
  and `senec-charger — service environment` sections of the exported
  `.env`. Common preservation path also seen in
  [user1](../user1/README.md).
- **Single InfluxDB token reused across all four roles** — donor sets
  `INFLUX_ADMIN_TOKEN = INFLUX_TOKEN_WRITE = INFLUX_TOKEN_READ =
  my-super-secret-admin-token` (with the candid `.env` comment "*to
  keep things simple, we use ONE token*"). HELIOS preserves all three
  plus the synthesized `INFLUX_TOKEN_READWRITE` at the same value
  rather than rotating them to distinct secrets — same passthrough as
  user21.
- **Forecast collector routes around ingest, hits InfluxDB directly** —
  donor's `forecast-collector` env has bare `INFLUX_HOST` (= default
  `influxdb`), while senec-collector / shelly-collector / mqtt-collector
  all use `INFLUX_HOST=ingest`. Forecast and the unmanaged
  `tibber-collector` / `senec-charger` write straight to InfluxDB,
  bypassing Ingest. HELIOS preserves the split routing on re-export.
- **Watchtower synthesized from defaults** — donor has
  `containrrr/watchtower` (no tag) running with `--scope solectrus
  --cleanup`. HELIOS canonicalizes the image to
  `containrrr/watchtower:latest` and re-emits the service with
  `WATCHTOWER_POLL_INTERVAL=86400` / `WATCHTOWER_SCOPE=solectrus` /
  `WATCHTOWER_CLEANUP=true` from `WATCHTOWER_DEFAULTS`, so the donor
  stays on their existing registry/repo rather than getting flipped
  to HELIOS' baseline `nickfedor/watchtower:latest` — and the
  configuration knobs land in the canonical env-var form instead of
  the donor's CLI-flag style.
