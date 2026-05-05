# Open TODOs

Remaining work, grouped by area.

## Configuration experience

- **Summary / review view after auto-import (scenario C).** Show the user what HELIOS detected, which services / variables it preserved as unmanaged, and which fields still need attention before the first edit.

## Sensor mapping

- **InfluxDB discovery during import.** When reverse-mapping an existing installation, query the running InfluxDB for actual measurements and fields and offer them as selectable values — instead of relying on literal `.env` contents.

## Update management

- **"Update now" button** to trigger an immediate Watchtower check via its HTTP API instead of waiting for the next interval.

## User experience

- **Link from Dashboard back to HELIOS.** Expose HELIOS' URL to the Dashboard service (e.g. as an env var) so Dashboard can show a "configure" link — users who start in Dashboard should be able to jump straight to the settings UI without knowing the HELIOS URL by heart.
- **Surface imported `volume_path` in the service management UI.** Read-only display of the resolved storage location (named volume name or absolute bind-mount path) for postgresql / influxdb / redis / ingest / reverse_proxy. Today the value is preserved through import/export but invisible to the user — only `config.yaml` reveals it. Editing stays out of scope; ADR-0003 keeps bind mounts as the default, and changing storage on a live stack is a destructive operation that warrants a separate flow.
