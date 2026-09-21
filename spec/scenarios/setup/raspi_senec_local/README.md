# raspi_senec_local

The plainest installation there is, and the baseline every other setup
scenario is read against. A Raspberry Pi on the home network, one
SENEC.Home V3 polled locally, no reverse proxy, no backup, no second source.

Three answers produce the whole stack. The one that matters most is the
first: picking SENEC for a single sensor enables the fifteen other sensors
the collector delivers, so the `.env` carries sixteen `INFLUX_SENSOR_*`
lines that nobody typed.

Everything the answers leave out is a default the survey supplies:
`schema: https`, `language: de` and `measurement: SENEC` on the SENEC screen,
`timezone: Europe/Berlin` on the general one.
