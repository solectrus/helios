<!--
Release notes for the next release. Add a line in the SAME commit that makes the
change. `README.md` in this directory carries the rules for what goes in and how
to word it.

Keep every section, an empty one included.
-->

## Before the update

- **Ingest has a new address.** Behind the built-in Traefik, Ingest now answers at `https://<domain>:4567`. The connection is encrypted, so the write token no longer travels in plain text. Plain HTTP and an IP address in place of the domain no longer work. Every external source that writes to Ingest needs the new address. The Ingest screen shows it
- **Taken-over Traefik rules are dropped.** HELIOS writes the routing of its own services itself now. A rule that put a rate limit or a password gate in front of the dashboard has to move into the configuration of that Traefik. A rule that made InfluxDB reachable under a subdomain, like `influxdb.<domain>`, stops working. InfluxDB now answers on the domain of the installation, and its settings show the address

## New features

- **HELIOS runs the MQTT broker.** A broker is the server that passes MQTT messages between devices. Until now every installation needed its own. HELIOS can run Mosquitto now. The MQTT settings switch it on, and its card shows the address that devices send to (#466)
- **A reverse proxy can use a shared network.** An external reverse proxy then reaches the installation over a Docker network that both sides use, instead of over published ports. No port of the installation stays open on the host

## Improvements

### Address & domain

- **One card instead of two.** The cards Host and Custom Domain are now the single card Address & Domain. The address is entered once, and every field explains what it means in the mode that runs. With the built-in Traefik, a button checks the domain before saving
- **HTTPS is on from the start** for an external reverse proxy. Such a proxy ends the encrypted connection itself. An installation that already runs in that mode keeps its own setting

### Settings and forms

- **Passwords, tokens and keys show as dots.** An eye button in the field shows the value. Password managers stay out of these fields

### Data sources

- **Every card says where the data comes from.** The answer is the device on the local network, the vendor cloud, or what devices send. The cards now carry the name of the source alone: SENEC, Shelly, MQTT and PV forecast

### Services

- **A blocked start says what blocks it.** The start stays visible. The reason appears in the status bar and on every service

### Import

- **An import stops on anything HELIOS cannot take over.** The message names what is in the way, a Traefik label or a Docker network. An installation with its own MQTT broker stops as well, because HELIOS runs the broker itself. The MQTT settings switch it on after the import (#466)

### Phone and screen reader

- **Explanations open on a tap, icon buttons get names.** On a phone the explanation opens for the age of a reading, the state of a service, the reason an action is blocked, and the notes on the backup and sensor screens. A screen reader can now name Start, Stop, Update, Logs and Clear cache (#480)

## Fixes

- **Collector and sensors use the same measurement.** A name entered by hand reaches every sensor of that source, and a later change carries through. Without a name, the forecast goes to `Forecast`, where the dashboard reads it. The dashboard no longer stays empty
- **A failed update says what stopped it.** An update of the whole installation keeps its log and its exit code. The services screen names the last line of the log
- **Addresses and links lead somewhere.** A pasted address is stored as the host name alone, without a scheme, a port or a path. A loopback address like localhost is refused, because a link built from it sends a device back to itself. A switch to the built-in Traefik hands port 3999 over to it, and the screen names the address where HELIOS comes back. The Open button works behind that Traefik too, and for a stopped service whose port is bound to one IP address of the host
- **An import keeps networks and routes.** The network of a parent stack survives, and so do the routes of a reverse proxy beside the stack. A proxy that HELIOS does not take over keeps the folder with its certificates. A proxy that HELIOS does take over routes as before, including the redirect from port 80 to HTTPS and the routes to InfluxDB and Ingest
- **An unmanaged service keeps its version.** A service that HELIOS does not manage is no longer offered an upgrade
- **A failed S3 transfer names the reason.** A backup and a restore to S3 both report why they stopped, for example a rejected access key or a bucket that cannot be reached
- **The preparation no longer fails.** Backup, restore and CSV import survive a service that restarts at the same moment
- **The support bundle hides private data.** The address of the machine and the email address for the certificates appear as placeholders, so a bundle attached to a public forum post no longer carries them. Each service now contributes its last 2000 log lines, up from 500

## Maintenance

- **Smaller corrections:** the wording is impersonal and the same everywhere, every confirmation carries a warning sign, a form with several screens turns a page without flicker, a link to another tab moves the mark in the main navigation, the focus mark stands out clearly, and a button that cannot be used no longer shows the hand cursor
- **The generated files name only what runs.** The `.env` file lists only the settings that the stack reads. The Traefik file lists only the services that are reachable, and explains every placeholder it carries
- **Updated to Ruby 4.0.7**
