<!--
Release notes for the next release. Add a line in the SAME commit that makes the change. The release skill takes this file, translates it, and empties it again.

What goes in: a change a user can see or feel. Not dependency bumps, refactorings, tests, CI, lint fixes. Reverted before the release? Delete the line.

How to write it: one line, English, the words of the user interface. Name what changed for the user, not how it was built. Add "(#466)" when an issue or a discussion drove the change. An issue or a discussion of the main repository needs the full name, as in "(solectrus/solectrus#5828)", because a bare number points at this repository. Under "Fixes", write what works now, never what was broken.

Keep the copy rules of the interface: no Docker vocabulary, no second-person address, no em dashes.

Keep every section, an empty one included.
-->

## New features

- Ingest: an external source can now deliver its values to Ingest, so a balcony power plant behind a smart home is covered as well. The address the source has to write to is shown in the Ingest settings and next to every affected sensor, and a switch there decides whether Ingest runs at all. An existing configuration that has such a source keeps the correction switched off, so the values reach the database as before until the source is redirected

## Improvements

- Address: the address of the machine is taken from the browser as long as the field is empty, so external sources can be named an address that works
- MQTT sensors: the data type follows from the sensor, so the survey no longer asks for it. A wrong answer used to stop the collector (solectrus/solectrus#5828)
- Total generation: the source page of inverter_power states when the single producers are added up and when the sensor replaces them (solectrus/solectrus#5828)
- Connection test: a test that fails on a loopback address says so, because such an address points a service at itself (solectrus/solectrus#5828)
- Time zone: the list now holds 137 zones with their offset, instead of 11
- Sensors: the list now arrives with the page itself, so the configuration opens without an empty moment
- Configuration menu: the marker moves to the selected entry the moment it is clicked
- Services: the rows arrive with the page, so the list no longer fills in row by row

## Fixes

- Configuration screens: the page no longer scrolls by a few pixels while everything is already in view
- House power: the hint names the excluded consumers by the label of the sensor list, one per line
- Dropdown lists: a long list inside a dialog stays complete and reacts to the keyboard, and a list no longer flares open once more while it closes (solectrus/solectrus#5828)
- Installation: an existing configuration file keeps all of its values, and the admin password is unique to the installation

## Maintenance

- Dependencies updated
