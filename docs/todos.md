# Open TODOs

Work still ahead, grouped by area. This list replaces the earlier phase-based roadmap.

## Configuration experience

- **Cross-chapter validation and dependency checks.** E.g. a wallbox configuration requires an inverter; a Shelly data source requires at least one mapped sensor. Today the surveys validate each chapter in isolation.
- **Summary / review view after auto-import (scenario C).** Show the user what HELIOS detected, which services / variables it preserved as unmanaged, and which fields still need attention before the first edit.
- **Web editor for unmanaged services and env vars.** Power-user feature: let users modify preserved services inline in HELIOS instead of editing `compose.yaml` by hand.

## Sensor mapping

- **InfluxDB discovery.** Auto-query available measurements and fields from the running InfluxDB instance and offer them as selectable values in the mapping UI — instead of requiring the user to type them.

## Log viewer

- **Free-text search** within a service's log output.
- **Filter by severity** (info / warn / error).
- **Filter by time range.**

## Update management

- **"Update now" button** to trigger an immediate Watchtower check instead of waiting for the next interval.
- **Changelog display.** Fetch release notes from GitHub and show them before updating.

## Operations / observability

- **Dedicated alert UI.** The status bar already shows overall state; extend it with a drill-down that lists affected services, detected errors, and troubleshooting hints.

## User experience

- **Link to the running SOLECTRUS Dashboard** from the HELIOS UI (with correct hostname / port / HTTPS detection).
- **Mobile-responsive polish.** The layout works on desktop today; revisit narrow viewports once the above features land.

## Platform

- **Opt-in telemetry** via `update.solectrus.de` — update checks and anonymous usage statistics. User must consent during initial setup.
