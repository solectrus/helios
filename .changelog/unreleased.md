<!--
Release notes for the next release. Add a line in the SAME commit that makes the
change. `README.md` in this directory carries the rules for what goes in and how
to word it.

Keep every section, an empty one included.
-->

## Before the update

## New features

## Improvements

## Fixes

- **A missing database token takes the existing one.** When a token for InfluxDB is missing from `config.yaml`, HELIOS now copies the existing admin token. InfluxDB knows this token, so Power Splitter keeps its access. (solectrus/solectrus#6149)

## Maintenance

- **Start screens no longer scroll without need.** The basic settings, the login and the start screen now fit the window.
