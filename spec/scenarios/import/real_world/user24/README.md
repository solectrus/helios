# user24

Real-world `compose.yaml.bak` + `.env.bak` from the SOLECTRUS user in
[solectrus/solectrus#5662](https://github.com/solectrus/solectrus/issues/5662)
("alle Daten weg"). An **evcc-fed MQTT stack** (PV, grid, battery,
wallbox, heatpump and a Buderus heatpump fleet all mapped via
`MAPPING_*`) plus **eight per-device `shelly-collector-*` services**
(`-dish`, `-cooler`, `-freezer`, `-wine`, `-wztechnik`, `-dryer`,
`-wash`, `-pctechnik`) — one container per Shelly plug — whose
measurements feed `INFLUX_SENSOR_CUSTOM_POWER_01..09`. One custom-power
sensor (`strom:allgemeinstrom`) is fed from MQTT, not Shelly. The donor
uses the legacy **`INFLUX_MEASUREMENT_PV`** naming, runs **`dozzle`** as
an unmanaged log viewer, and the file is the usual real-world mess:
commented-out alternatives, a duplicated `INFLUX_SENSOR_GRID_EXPORT_LIMIT`
line, MQTT `MAPPING_*_POSITIVE`/`_NEGATIVE` sign splits, and typo-laden
German comments. Anonymized (tokens, passwords) but otherwise untouched.

The fixture exercises the **mixed Shelly representation** that no prior
fixture covers: the same eight physical Shellys appear both as
per-device collector services *and* as `INFLUX_SENSOR_CUSTOM_POWER_*`
mappings on the dashboard. The importer (since `0f234539`, "represent
each device once, on its sensor") now folds each Shelly onto its
consuming sensor and emits **no** standalone `shelly.devices` entry, so
the export's `SHELLY_HOST` and `INFLUX_MEASUREMENT` CSVs stay
length-matched (8 = 8) and the canonical single `shelly-collector`
boots cleanly. This snapshot is the regression guard for that import
path.

## Relationship to the reported bug

The crash in #5662 (shelly-collector dying on
`SHELLY_HOST count (9) must match INFLUX_MEASUREMENT count (16)`) is
**not** reproduced by this `.bak` → import round-trip, because the
import bug is already fixed. The donor migrated to HELIOS *before*
`0f234539`, so their persisted `config.yaml` carries every Shelly
*twice* — once as a `custom_power` sensor and once as a standalone
`shelly.devices` entry. Upgrading HELIOS does not re-import, so the
corrupted `config.yaml` survives and the **export** side still
concatenates both representations into mismatched CSVs. That remaining
export-side defect is covered separately (it needs a `config.yaml`
fixture, not a `.bak` one, since a fresh import no longer produces the
duplication).
