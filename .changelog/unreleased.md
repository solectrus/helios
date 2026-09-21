<!--
Release notes for the next release. Add a line in the SAME commit that makes the change. The release skill takes this file, translates it, and empties it again.

What goes in: a change a user can see or feel. Not dependency bumps, refactorings, tests, CI, lint fixes. Reverted before the release? Delete the line.

How to write it: one line, English, the words of the user interface. Name what changed for the user, not how it was built. Add "(#466)" when an issue or a discussion drove the change. An issue or a discussion of the main repository needs the full name, as in "(solectrus/solectrus#5828)", because a bare number points at this repository. Under "Fixes", write what works now, never what was broken.

Keep the copy rules of the interface: no Docker vocabulary, no second-person address, no em dashes.

Keep every section, an empty one included.
-->

## New features

## Improvements

- Ingest: behind the built-in Traefik the write address now uses HTTPS, on the same domain as the rest of the installation. An external source sends its token over an encrypted connection, and the installation opens no plain port of its own. The Ingest screen names the new address. Every external source that already writes to Ingest needs that address, because the old one on port 4567 answers no longer
- Address & domain: choosing the built-in Traefik now says that HELIOS itself follows the domain, on port 3999, and offers a check of that domain before the mode is saved. A domain that leads somewhere else is named at once, instead of taking the screen with it
- On a phone, an explanation now opens on a tap: the age of a reading, the state of a service, the reason an action is blocked, and the notes on the backup and sensor screens (#480)
- Keyboard and screen reader: a button now shows its label when the focus reaches it, and a button that carries only an icon now says its name (#480)
- Configuration forms: every password, token and access key now appears as dots, and an eye button in the field shows the value
- Configuration forms: a password manager now stays out of these fields
- The wording no longer addresses the reader, and it is the same everywhere
- Navigation: a warning sign now points at a setting that is still open, from the Configuration tab down to the setting itself. The tab opens the screen it marks
- Configuration: the Basic Settings screen is now named Settings
- Settings: the screen now leads with the one setting that has to be filled in, and the form asks one question per screen. Everything else is optional and already carries a sensible value
- Confirmations: every question now carries a warning sign, yellow where a decision is reversed and red where data is lost
- Keyboard use: the focus mark on a button now stands out clearly
- Services: a start that cannot run now stays visible and names what blocks it, in the status bar and on every service
- Buttons: one that cannot be used no longer shows the hand cursor
- Generated for Traefik: the header now explains every placeholder the file carries
- Settings: the Host card and the Custom Domain card are now one card, named Address & Domain. The address is entered once, and the form says what it stands for: the machine on the local network, the domain the built-in Traefik answers on, or the domain an external reverse proxy routes
- Settings: a field now explains itself in the mode that is running. Making InfluxDB reachable names the address it leads to, the host port of the dashboard says when it has no effect, and the IP ranges of a proxy say when they are needed

## Fixes

- Configuration forms: a form with several screens now turns a page without flicker, also on quick clicks
- Navigation: a link that leads to another tab now moves the mark in the main navigation with it
- Address of the machine: an address pasted out of the browser is now stored as the name alone. HELIOS removes a scheme, a port and a path, so every link and every rule built from the address leads somewhere. The field can stay empty, and the published port is used instead
- Address of the machine: a loopback address such as localhost is now refused while it is typed, because every link derived from it sends a device back to itself. An address of that kind is dropped on update, and dropped from an imported installation as well. The generated files no longer fall back to localhost either
- Import: a stack routed by a reverse proxy that runs beside it, over a shared network, is now recognized as such. Its address and its HTTPS setting reach the form instead of staying hidden
- Generated for Docker: the .env file now lists only the settings the stack reads. It no longer names a certificate folder that the stack does not use
- Backup to S3: a backup or a restore that fails now reports the reason, for example a rejected access key or a bucket that cannot be reached
- Backup, restore and CSV import: the preparation no longer fails when a service is renewed at the same moment
- Services: the Open button of a stopped service now uses the right port again where the published ports are bound to one host IP address
- Support bundle: the address of the machine and the email address for the certificates now appear as placeholders, in every file of the bundle. A bundle attached to a public forum post no longer carries them
- Address & domain: an installation behind an nginx or an Apache is recognized as one, so the form offers its settings and the HTTPS setting it needs stays in place
- Address & domain: the IP ranges of an upstream proxy are dropped once the address is reached directly. They belong to a proxy that is no longer there, and the dashboard no longer believes a request from those ranges about who sent it
- Generated for Traefik: the file now names only the services that are reachable. An InfluxDB kept inside the stack no longer gets a route that leads nowhere

## Maintenance

- Support bundle: every service now contributes its last 2000 log lines instead of 500
- Updated to Ruby 4.0.7
