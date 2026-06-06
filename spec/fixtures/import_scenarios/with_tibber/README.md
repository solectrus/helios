# with_tibber

Minimal stack extended with a `tibber-collector` service. Exercises the
fully-managed Tibber section for a collector that has no
associated sensors and writes a standalone prices measurement.

## Highlights

- **`tibber-collector` is a managed HELIOS service** → imported into the typed
  `tibber:` section (`token`, `measurement`), not `_unmanaged.services`. On
  export HELIOS regenerates the service and emits `TIBBER_TOKEN` plus the
  canonical `INFLUX_MEASUREMENT_PRICES` in `.env`.
- **Measurement canonicalization** — the donor writes via
  `INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_TIBBER}` (legacy alias, value
  `Tibber`). HELIOS reads the resolved measurement into `tibber.measurement`
  and re-emits it as `INFLUX_MEASUREMENT_PRICES=Tibber`; the legacy alias is
  dropped as dead weight.
- **`TIBBER_INTERVAL` is not managed** — it is not UI-configurable, so HELIOS
  drops it on import and the re-exported collector relies on its built-in
  default.
- **`sensors: {}`** — no sensors at all. Tibber is not sensor-driven, so the
  top-level `sensors:` key stays empty rather than being omitted.
- **A Tibber collector without a charger** — the only thing HELIOS collects
  prices for is the SENEC charger (`senec_charger:`), and this stack has none.
  The import preserves the running collector anyway rather than dropping a
  service the donor stack relies on, so the section round-trips without any UI
  offering it: the charger chip needs a locally-queried SENEC battery
  (`Configuration#senec_charger_offered?`) and this stack has no SENEC, Shelly,
  forecast or MQTT collector at all.
