# user6

Real-world `compose.yml` + `.env` from a SOLECTRUS user running behind
Traefik with a self-hosted `mosquitto` broker and a `pgadmin` database UI.
Anonymized but otherwise untouched.

## Import-rejection fixture

This stack is **refused by `Import::CompatibilityCheck`**: it ships two images
HELIOS neither manages nor allowlists as companions — `eclipse-mosquitto`
(`mosquitto` service) and `dpage/pgadmin4` (`pgadmin` service). Its
`amir20/dozzle` log viewer _is_ an allowlisted companion, so the rejection
screen names only `mosquitto` and `pgadmin`.

It is therefore **not** a round-trip fixture: it has no `config.yaml`,
`compose.yaml`, or `.env`, and does not run in `scenarios_spec.rb`. Only the
donor `.bak` files are kept. The fixture is exercised by
`spec/services/import/compatibility_check_spec.rb` as the mixed-rejection case
(foreign services flagged, allowlisted companion kept).

The Traefik-adoption round-trip coverage this snapshot once provided now lives
in the synthetic `with_custom_traefik` scenario.
