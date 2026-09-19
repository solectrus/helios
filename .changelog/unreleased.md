<!--
Release notes for the next release. Add a line in the SAME commit that makes the change. The release skill takes this file, translates it, and empties it again.

What goes in: a change a user can see or feel. Not dependency bumps, refactorings, tests, CI, lint fixes. Reverted before the release? Delete the line.

How to write it: one line, English, the words of the user interface. Name what changed for the user, not how it was built. Add "(#466)" when an issue or a discussion drove the change. An issue or a discussion of the main repository needs the full name, as in "(solectrus/solectrus#5828)", because a bare number points at this repository. Under "Fixes", write what works now, never what was broken.

Keep the copy rules of the interface: no Docker vocabulary, no second-person address, no em dashes.

Keep every section, an empty one included.
-->

## New features

## Improvements

- On a phone, a tap now shows the hint that a mouse shows on hover (#480)
- Configuration forms: every password, token and access key now appears as dots, and an eye button in the field shows the value
- Configuration forms: a password manager now stays out of these fields
- The wording no longer addresses the reader, and it is the same everywhere
- Navigation: a warning sign now points at a setting that is still open, from the Configuration tab down to the setting itself. The tab opens the screen it marks
- Status bar: the note about an incomplete configuration is gone, because the configuration screens now mark what is missing
- Configuration: the Basic Settings screen is now named Settings
- Settings: the screen now leads with the one setting that has to be filled in, and the form asks one question per screen. Everything else is optional and already carries a sensible value
- Confirmations: every question now carries a warning sign, yellow where a decision is reversed and red where data is lost
- Keyboard use: the focus mark on a button now stands out clearly

## Fixes

- Configuration forms: a form with several screens now turns a page without flicker, also on quick clicks
- Navigation: a link that leads to another tab now moves the mark in the main navigation with it
- Address of the machine: a loopback address such as localhost is now refused while it is typed, because every link derived from it sends a device back to itself. The field can stay empty instead, and the published port is then used
- Backup to S3: a backup or a restore that fails now reports the reason, for example a rejected access key or a bucket that cannot be reached
- Backup, restore and CSV import: the preparation no longer fails when a service is renewed at the same moment

## Maintenance

- Support bundle: every service now contributes its last 2000 log lines instead of 500
- Updated to Ruby 4.0.7
