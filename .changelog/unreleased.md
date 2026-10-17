<!--
Release notes for the next release. Add a line in the SAME commit that makes the
change. `README.md` in this directory carries the rules for what goes in and how
to word it.

Keep every section, an empty one included.
-->

## Before the update

## New features

- **Sensors for up to five electric cars.** Each car has its own group with odometer, range, battery level, plug state and location. The car evaluation of SOLECTRUS 1.4 reads these sensors. Older dashboard versions ignore them. (#570)

## Improvements

- **The address lookup for cars has a setting.** SOLECTRUS 1.4 gets the addresses of car locations and charging sessions from Nominatim, the address service of OpenStreetMap. The new "Geocoding" setting selects the public server, a server of the operator's own, or no lookup at all. It appears when a car is configured and the dashboard runs on the "Development" channel.

## Fixes

## Maintenance
