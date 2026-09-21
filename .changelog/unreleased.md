<!--
Release notes for the next release. Add a line in the SAME commit that makes the change. The release skill takes this file, translates it, and empties it again.

What goes in: a change a user can see or feel. Not dependency bumps, refactorings, tests, CI, lint fixes. Reverted before the release? Delete the line.

How to write it: one line, English, the words of the user interface. Name what changed for the user, not how it was built. Add "(#466)" when an issue or a discussion drove the change. An issue or a discussion of the main repository needs the full name, as in "(solectrus/solectrus#5828)", because a bare number points at this repository. Under "Fixes", write what works now, never what was broken.

Keep the copy rules of the interface: no Docker vocabulary, no second-person address, no em dashes.

Keep every section, an empty one included.
-->

## New features

## Improvements

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
- Custom domain: the form that selects an external reverse proxy now asks for the domain that proxy routes. The file generated for Traefik carries that domain at once, in place of a placeholder

## Fixes

- Configuration forms: a form with several screens now turns a page without flicker, also on quick clicks
- Navigation: a link that leads to another tab now moves the mark in the main navigation with it
- Address of the machine: an address pasted out of the browser is now stored as the name alone. HELIOS removes a scheme, a port and a path, so every link and every rule built from the address leads somewhere. A custom domain is stored the same way. The field can stay empty, and the published port is used instead
- Address of the machine: a loopback address such as localhost is now refused while it is typed, because every link derived from it sends a device back to itself. An address of that kind is dropped on update, and dropped from an imported installation as well. The generated files no longer fall back to localhost either
- Custom domain over the built-in Traefik: the dashboard now learns the domain it answers on, in place of the address of the machine on the local network. It accepts a request from that domain again
- Generated for Docker: the .env file now lists only the settings the stack reads. It no longer names a certificate folder that the stack does not use
- Backup to S3: a backup or a restore that fails now reports the reason, for example a rejected access key or a bucket that cannot be reached
- Backup, restore and CSV import: the preparation no longer fails when a service is renewed at the same moment
- Support bundle: the custom domain, the address of the machine and the email address for the certificates now appear as placeholders, in every file of the bundle. A bundle attached to a public forum post no longer carries them
- Services: the Open button of a stopped service now uses the right port again where the published ports are bound to one host IP address

## Maintenance

- Support bundle: every service now contributes its last 2000 log lines instead of 500
- Updated to Ruby 4.0.7
