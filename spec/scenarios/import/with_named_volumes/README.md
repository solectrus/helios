# with_named_volumes

Installation that uses **Docker named volumes** (`volume-name:/path`) instead
of bind mounts — both for SOLECTRUS data services and for an unmanaged
`dozzle` sidecar. Verifies that named-volume mounts survive a round-trip so
existing data keeps resolving to the same Docker volume after HELIOS takes
over.

## Highlights

- **Top-level `volumes:` block preserved** under `_unmanaged.volumes` and
  re-emitted on export. Named volumes referenced by both managed and
  unmanaged services keep their declarations (`influxdb-data`,
  `postgres-data`, `redis-data`, `dozzle-data`).
- **Managed services keep their named-volume source.** `VolumeResolver`
  recognizes Docker volume names alongside absolute host paths and stores
  them as `volume_path` in `config.yaml`. The exported `.env` therefore
  emits e.g. `INFLUX_VOLUME_PATH=influxdb-data`, so the existing volume
  is reused on first start.
- **Volume metadata round-trips verbatim.** `dozzle-data: { driver: local }`
  comes back unchanged in the regenerated `compose.yaml`.
- **Unmanaged service keeps its named-volume reference** (`dozzle-data:/data`)
  inside `_unmanaged.services.dozzle.volumes` — backed by the top-level
  declaration so Compose doesn't fall back to an anonymous volume.
