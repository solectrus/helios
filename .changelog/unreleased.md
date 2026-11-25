<!--
Release notes for the next release. Add a line in the SAME commit that makes the
change. `README.md` in this directory carries the rules for what goes in and how
to word it.

Keep every section, an empty one included.
-->

## Before the update

## New features

- **Sensors for the range of the PV forecast.** Two new sensors read the lower and the upper limit of the PV forecast. The dashboard draws the range between them, for now only on the Development channel. The forecast collector delivers them with pvnode, a site ID and the Plus plan. With this setup, HELIOS enables both sensors on its own. Another software can also write them externally.

## Improvements

- **The installer shows the version of HELIOS.** Its welcome screen names the release, for example v1.7.0, instead of the date of the last change to the script.

## Fixes

- **Temperature forecast and clear-sky forecast only with pvnode.** Of all forecast providers, only pvnode delivers these two values. With forecast.solar or Solcast, the sensor settings no longer offer the forecast collector as their source and say why.

## Maintenance
