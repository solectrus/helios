# user2

Real-world `compose.yaml` + `.env` from a SOLECTRUS user running a self-built,
heavily customized stack (13 custom power sensors, multi-plane pvnode
forecasts, a Tibber price feed, a self-hosted MQTT broker). Anonymized but
otherwise untouched.

## Import-rejection fixture

This stack is **refused by `Import::CompatibilityCheck`**: it ships a
self-hosted `mosquitto` MQTT broker (`eclipse-mosquitto:2.0`), an image HELIOS
neither manages nor allowlists as a companion. HELIOS regenerates
`compose.yaml` in full and only adopts a stack whose every service it can
faithfully reproduce, so the import is refused upfront with the offending
service named on the rejection screen.

It is therefore **not** a round-trip fixture: it has no `config.yaml`,
`compose.yaml`, or `.env`, and does not run in `scenarios_spec.rb`. Only the
donor `.bak` files are kept. The fixture is exercised by
`spec/services/import/compatibility_check_spec.rb` as the
single-foreign-service rejection case.
