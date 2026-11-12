<!--
Release notes for the next release. Add a line in the SAME commit that makes the
change. `README.md` in this directory carries the rules for what goes in and how
to word it.

Keep every section, an empty one included.
-->

## Before the update

## New features

## Improvements

- **A refused import explains how to split the stack.** When HELIOS cannot take over some services, it now says to move them into a directory of their own with their own `.env`, and to leave the `.env` of SOLECTRUS unchanged. The advice about the MQTT broker appears only when a broker is listed. (solectrus/solectrus#6149)

- **A new password signs out all other browsers.** A login is now valid only for the password it was made with. The browser that changes the password stays logged in. After this update, every browser must log in one time again.
- **The login pauses after too many attempts.** After 10 attempts within three minutes, the login refuses further attempts for a few minutes. This makes it much slower to guess the password.

## Fixes

- **A missing database token takes the existing one.** When a token for InfluxDB is missing from `config.yaml`, HELIOS now copies the existing admin token. InfluxDB knows this token, so Power Splitter keeps its access. (solectrus/solectrus#6149)

## Maintenance

- **Start screens no longer scroll without need.** The basic settings, the login and the start screen now fit the window.
