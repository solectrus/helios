# Open TODOs

Remaining work, grouped by area.

## Configuration experience

- **Summary / review view after auto-import (scenario C).** Show the user what HELIOS detected, which services / variables it preserved as unmanaged, and which fields still need attention before the first edit.

## Service support

- **First-class support for `tibber-collector` and `senec-charger`.** Both are currently only preserved as unmanaged services. Make them first-class managed services with proper survey-driven configuration, instead of passing them through untouched.

## Sensor mapping

- **InfluxDB discovery in the sensor mapping UI.** When configuring a sensor's measurement / field, let the user pick from the values that actually exist in the running InfluxDB instead of typing them freehand. Query the live DB (an `InfluxDb::Client` already exists for latest-value reads) for available measurements and their fields and offer them as selectable choices.
