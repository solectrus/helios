# Open TODOs

Remaining work, grouped by area.

## Configuration experience

- **Summary / review view after auto-import (scenario C).** Show the user what HELIOS detected, which services / variables it preserved as unmanaged, and which fields still need attention before the first edit.

## Sensor mapping

- **InfluxDB discovery during import.** When reverse-mapping an existing installation, query the running InfluxDB for actual measurements and fields and offer them as selectable values — instead of relying on literal `.env` contents.

## Update management

- **"Update now" button** to trigger an immediate Watchtower check via its HTTP API instead of waiting for the next interval.

## User experience

- **Mobile-responsive polish.** The layout works on desktop today; revisit narrow viewports once the above features land.
- **Link from Dashboard back to HELIOS.** Expose HELIOS' URL to the Dashboard service (e.g. as an env var) so Dashboard can show a "configure" link — users who start in Dashboard should be able to jump straight to the settings UI without knowing the HELIOS URL by heart.
