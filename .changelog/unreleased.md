<!--
Release notes for the next release. Add a line in the SAME commit that makes the change. The release skill takes this file, translates it, and empties it again.

What goes in: a change a user can see or feel. Not dependency bumps, refactorings, tests, CI, lint fixes. Reverted before the release? Delete the line.

How to write it: one entry, English, the words of the user interface. Start with a bold label that names the change, then one or two short sentences that say what it means for the user, not how it was built. Add "(#466)" when an issue or a discussion drove the change. An issue or a discussion of the main repository needs the full name, as in "(solectrus/solectrus#5828)", because a bare number points at this repository. Under "Fixes", write what works now, never what was broken.

How to order it: "Before the update" comes first and holds what an installation that already runs has to act on, an address that changes or a setting that goes. It stays empty otherwise. Then the most important entry first. Group a long section with "###" subheadings by topic. Small polish goes to "Maintenance", collected in one line, or it goes out.

Keep the copy rules of the interface: no Docker vocabulary, no second-person address, no em dashes.

Keep every section, an empty one included.
-->

## Before the update

- **An external source that writes to Ingest needs a new address.** Behind the built-in Traefik, Ingest answers at `https://<domain>:4567` now, on the domain of the installation. Port 4567 stays open, but plain HTTP and an IP address in place of the domain no longer reach Ingest. The Ingest screen names the new address
- **A Traefik rule an earlier import took over is dropped.** HELIOS writes the routing of its own services now. If such a rule put a rate limit or a password gate in front of the dashboard, that setting belongs in the configuration of that Traefik from now on
- **An InfluxDB that a taken-over rule made reachable answers on the domain of the installation.** It stays reachable, and the InfluxDB settings name the address. A rule that named a subdomain, such as `influxdb.<domain>`, leads nowhere after the update

## New features

- **Reverse proxy over a shared network:** an external reverse proxy reaches the installation over a Docker network the two share, instead of over ports published on the host. The form asks for the name of that network and for the entrypoint of a Traefik that reads routes off it. The routed services join the network, HELIOS writes the routes, and no port of the installation stays open on the host. A network name that no network on the host answers to is refused, where it is typed and again before a start
- **Ingest over HTTPS:** behind the built-in Traefik the write address uses HTTPS, on the same domain as the rest of the installation. An external source sends its token over an encrypted connection, and no plain port is opened for it. The Ingest screen names the new address
- **Domain check before saving:** choosing the built-in Traefik offers a check of the domain first. A domain that leads somewhere else is named at once, instead of taking the screen with it

## Improvements

### Address & domain

- **One card instead of two:** the Host card and the Custom Domain card are now the card Address & Domain. The address is entered once, and the form says what it stands for: the machine on the local network, the domain the built-in Traefik answers on, or the domain an external reverse proxy routes
- **Every field explains itself in the running mode:** making InfluxDB reachable names the address it leads to, and the IP ranges of a proxy say when they are needed
- **HELIOS follows the domain:** the built-in Traefik serves HELIOS itself on port 3999, and the setting says so
- **HTTPS is on from the start** for an external reverse proxy, because such a proxy ends the TLS connection. An installation that already runs that mode keeps its own setting
- **An empty host IP names its consequence:** Dashboard, InfluxDB, Ingest and HELIOS then listen on every network interface and are reachable past the proxy and its HTTPS. A server with a public address needs a value here
- **The generated Traefik file explains every placeholder** it carries

### Settings and forms

- **The card Network is gone,** and its two questions moved to the cards they belong to. The port of the dashboard is asked under Address & Domain, and only in the modes that publish one. The permission to embed the interface into another website is asked under Access protection
- **Settings leads with the one setting that has to be filled in,** and asks one question per screen. Everything else is optional and already carries a sensible value. The screen Basic Settings is now named Settings
- **Passwords, tokens and access keys appear as dots,** an eye button in the field shows the value, and a password manager stays out of these fields
- **A warning sign points at a setting that is still open,** from the Configuration tab down to the setting itself. The tab opens the screen it marks
- **Every confirmation carries a warning sign,** yellow where a decision is reversed and red where data is lost

### Services

- **A start that cannot run stays visible and names what blocks it,** in the status bar and on every service

### Import

- **An installation whose routing HELIOS cannot write again is refused,** with the Traefik labels named, instead of losing them on the first save after the import

### Phone and keyboard

- **On a phone an explanation opens on a tap:** the age of a reading, the state of a service, the reason an action is blocked, and the notes on the backup and sensor screens (#480)
- **A button that carries only an icon says its name,** so a screen reader can name Start, Stop, Update, Logs and Clear cache (#480)

## Fixes

### Sensors & measurements

- **A measurement name of your own reaches the sensors.** Naming the InfluxDB measurement of the SENEC collector left every sensor reading the standard name, so the dashboard stayed empty. Collector and sensors now name the same measurement, and a later change to the name carries through
- **The forecast collector and the dashboard agree on where the forecast lands.** Without an explicit name, HELIOS told the collector to write into `forecast` while the dashboard read from `Forecast`. Both name `Forecast` now, which is what the collector writes into on its own

### Address & domain

- **Starting all services hands over the port HELIOS holds:** choosing the built-in Traefik moves port 3999 from HELIOS to Traefik, and the start now carries HELIOS itself, so Traefik gets the port. The screen then names the address HELIOS comes back at. The way back works the same
- **A pasted address is stored as the host name alone:** a scheme, a port and a path are removed, so every link and every rule built from the address leads somewhere. The field can stay empty, and the published port is used instead
- **A loopback address such as localhost is refused while it is typed,** because every link derived from it sends a device back to itself. An address of that kind is dropped on update and on import, and the generated files no longer fall back to it either
- **The IP ranges of an upstream proxy are dropped once the address is reached directly.** They belong to a proxy that is no longer there, and the dashboard no longer believes a request from those ranges about who sent it
- **The HELIOS screen carries an Open button behind the built-in Traefik as well,** leading to the same address every other place names
- **The Open button of a stopped service uses the right port again** where the published ports are bound to one host IP address

### Services

- **An update of the whole installation that fails says what stopped it.** The run keeps its log and its exit code, and the services screen names the last line of it

### Import

- **An installation on a Docker network of a parent stack keeps that network.** Every service joins it again after the import, and the published ports stay
- **An installation routed by a reverse proxy beside it keeps the routes.** The network, the entrypoint and the certificate resolver are read from the running stack and written again
- **An InfluxDB that a reverse proxy routes counts as reachable,** so it stays reachable after the import
- **An installation on a Docker network that HELIOS cannot write again is refused,** with the network named, instead of losing it without a word
- **A reverse proxy taken over on import routes the installation as before.** Port 80 sends a request on to HTTPS again, a port that answers nothing is closed, and making InfluxDB reachable takes effect behind such a proxy. Ingest is routed the same way

### Generated files

- **The .env file lists only the settings the stack reads.** It no longer names a certificate folder that the stack does not use
- **The Traefik file names only the services that are reachable.** An InfluxDB kept inside the stack no longer gets a route that leads nowhere

### Backup and support bundle

- **A backup or a restore to S3 that fails reports the reason,** for example a rejected access key or a bucket that cannot be reached
- **Backup, restore and CSV import no longer fail in the preparation** when a service is renewed at the same moment
- **The support bundle keeps the address of the machine and the email address for the certificates out of every file.** Both appear as placeholders, so a bundle attached to a public forum post no longer carries them

### Interface

- **A form with several screens turns a page without flicker,** also on quick clicks
- **A link that leads to another tab moves the mark in the main navigation with it**

## Maintenance

- **The support bundle collects the last 2000 log lines per service** instead of 500
- **Smaller corrections to the interface:** the wording no longer addresses the reader and is the same everywhere, the focus mark stands out clearly, and a button that cannot be used no longer shows the hand cursor
- **Updated to Ruby 4.0.7**
