<!--
Release notes for the next release. Add a line in the SAME commit that makes the change. The release skill takes this file, translates it, and empties it again.

What goes in: a change a user can see or feel. Not dependency bumps, refactorings, tests, CI, lint fixes. Reverted before the release? Delete the line.

How to write it: one line, English, the words of the user interface. Name what changed for the user, not how it was built. Add "(#466)" when an issue or a discussion drove the change. An issue or a discussion of the main repository needs the full name, as in "(solectrus/solectrus#5828)", because a bare number points at this repository. Under "Fixes", write what works now, never what was broken.

Keep the copy rules of the interface: no Docker vocabulary, no second-person address, no em dashes.

Keep every section, an empty one included.
-->

## New features

## Improvements

- On a phone, a tap on a value, a status dot or an info icon shows the hint that a mouse shows on hover (#480)
- Configuration forms: a password, a token and an access key are covered, and an eye button in the field uncovers one for a look. Before, some forms showed the value and others hid it
- Configuration forms: a password manager stays out of these fields. Its icon no longer covers the eye button, and it no longer offers a login that belongs elsewhere
- The interface no longer addresses the reader. Forms, dialogs and messages state the fact instead, and the wording is now the same everywhere
- Status bar: the note about an incomplete configuration is gone. The configuration screens mark what is missing next to the setting it belongs to
- Navigation: a warning sign points at a setting that is still open, from the Configuration tab down to the setting itself. The color marks the one step that leads on. The levels already opened keep the sign in the background
- Configuration: the Configuration tab opens the screen its warning sign marks. A setting that is still empty leads to the settings, a source that misses a field leads to the data sources
- Settings: the screen leads with the one setting that has to be filled in. A check next to it confirms the value is there, a warning sign says it is still missing. Everything below the line is optional and already carries a sensible value
- Basic settings: the form asks one question per screen, the commissioning date, then the timezone, then the currency
- Confirmations: every question now carries the warning sign, yellow where a decision is reversed and red where data is lost

## Fixes

- Configuration forms: a form with several screens turns a page without a strip flashing below the buttons
- Navigation: a link that leads to another tab moves the mark in the main navigation with it. Before, a link such as the one from the Services screen to the sensors left the mark on the tab it started from
- Address of the machine: a loopback address such as localhost is refused while it is typed. Everything derived from it sent a device or a browser back to itself, from the link to the dashboard to the address devices publish to. The field may be left empty instead, and the published port is then used

## Maintenance

- Support bundle: the logs reach much further back. Every service now contributes its last 2000 lines instead of 500
- Updated to Ruby 4.0.7
