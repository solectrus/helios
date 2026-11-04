<!--
Release notes for the next release. Add a line in the SAME commit that makes the
change. `README.md` in this directory carries the rules for what goes in and how
to word it.

Keep every section, an empty one included.
-->

## Before the update

## New features

- **Development channel gets a service for fuel prices.** The dashboard on the development channel compares the cost of an electric car with a combustion car. The new service reads the prices of petrol, diesel and LPG once a week for this comparison. HELIOS adds it when a car with an odometer is set up, the country is a member state of the European Union and the currency is the euro. On this channel, the basic settings have a new question for the country. Until it is answered, HELIOS takes the country from the timezone. After the update, the service must be started once in HELIOS. Installations on the stable channel see no change.

## Improvements

- **The dashboard links to the HELIOS address in use.** HELIOS reports the address it was last opened at, like the IP address in the home network. The menu of the dashboard opens HELIOS there, also when the dashboard itself runs behind a domain (solectrus/solectrus#6092).

## Fixes

## Maintenance
