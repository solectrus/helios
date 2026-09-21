# vm_cloud_traefik

A rented virtual machine under its own domain, and the counterpart to
`raspi_senec_local`. No address in this stack names a device on a home
network. The SENEC is read through the SENEC account, a managed Traefik
answers the domain, and the backup goes to S3 storage.

## The address changes twice

The browser opens HELIOS at the bare address of the machine, so the first
save adopts `203.0.113.10` as `app_host`. The proxy screen asks for the
address itself, and the domain replaces the adopted one. Only the domain
reaches the snapshot, on the Traefik router of each service and as
`APP_HOST`.

The mode also decides what reaches the machine. A proxy that terminates TLS
turns on `FORCE_SSL`, and only Traefik still publishes ports. In
`raspi_senec_local` the dashboard holds 3000 and HELIOS holds 3999 on the
host itself.

## What the model decides

A SENEC.Home 4 has no local access. The screen therefore never shows the
access type, and sets it to `cloud` on its own. The answers name the model
and the account, and nothing else about the collector.

The polling interval follows from the model too. The survey derives 60
seconds for a Home 4, against 300 seconds for a V3 over the cloud and 5
seconds for local access.

## Sensors the collector leaves empty

One answer picks SENEC, and HELIOS enables the sixteen sensors the collector
can deliver. Several of them receive nothing here. The cloud adapter reports
no `mpp*` values and no `power_ratio`. `case_temp` and the system status
arrive only in the full request mode, and the SENEC screen says that a Home 4
never reports the system status.

The snapshot holds that on purpose. HELIOS enables the full set, and a sensor
without data stays empty in the dashboard.

## The backup stays out of the stack

HELIOS makes the backups itself, so the S3 credentials stay in
`config.yaml`. Neither `compose.yaml` nor `.env` carries any of them. The
schedule is the one answer in this family that re-anchors a timer, because
saving it calls `BackupScheduler.reschedule!`.
