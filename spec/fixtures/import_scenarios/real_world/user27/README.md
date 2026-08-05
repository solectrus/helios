# user27

Real-world `compose.yaml.bak` + `.env.bak` from a SOLECTRUS user who adopted
a long-running stack with HELIOS v1.2.1 (issue #377). No collector talks to
an inverter directly: everything arrives over MQTT, from an **Enphase Envoy**
(`envoy/json`), **evcc** loadpoints (charge power, car connected, vehicle
SoC), **ESPAltherma** for a Daikin heat pump (`espaltherma/ATTR`) and a dozen
**Shelly plugs published as plain MQTT topics** rather than through
`shelly-collector` — 28 `MAPPING_*` blocks in total, writing into custom
German measurement names (`pv-messung`, `waschmaschine`, `ALTHERMA`, …).
Alongside it a **forecast.solar** collector with three roof configurations,
the **power-splitter**, **watchtower**, InfluxDB 2.7 and PostgreSQL 16.

The fixture exercises three quirks:

**A `$` inside the InfluxDB token — the reason this snapshot exists.**
`INFLUX_ADMIN_TOKEN=my-influx-token$secret` is unquoted, so Docker Compose
expands `$secret` to nothing while reading `.env` and the containers only
ever received `my-influx-token` — the token InfluxDB was actually initialized
with. HELIOS read the literal instead and quoted it on export, which disabled
the expansion: every recreated service authenticated with a token InfluxDB
had never seen, while the containers still running kept working. The import
must therefore yield `my-influx-token` for all four `token_*` fields.

**The same value arriving from two sources.** `token_readwrite` is not read
off `.env` at all but off the power-splitter's
`INFLUX_TOKEN=${INFLUX_ADMIN_TOKEN}`, which the importer resolves through
real `docker compose config`. That path was always correct, so the donor's
single token used to land in `config.yaml` as **two different values** — the
literal in three fields, the expanded one in the fourth. The snapshot pins
them back together, which is what makes it a regression guard for the whole
class: `.env` and `compose.yaml` have to agree on what a value means.

**Single-quoted values that contain `$`.** The `MAPPING_*_JSON_FORMULA`
entries are JSONPath expressions in the literal quoting form
(`'round({$.meters.pv.agg_p_mw} / 1000)'`). Compose passes those through
untouched, so the reader must not expand them — the mirror image of the first
quirk, and the reason interpolation cannot simply be applied to every value.

Legacy leftovers ride along: `FORECAST_INFLUX_MEASUREMENT`, a non-canonical
alias from the 2024 Online Configurator, and `INFLUX_POLL_INTERVAL`, ignored
by the dashboard since v1.2.0. The donor already contains a `helios` service,
because HELIOS was installed into the running stack before adopting it.
