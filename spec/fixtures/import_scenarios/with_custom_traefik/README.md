# with_custom_traefik

Synthetic stack exercising the **Traefik adoption** path: a SOLECTRUS stack
sitting behind a Traefik reverse proxy that was hand-configured with quirks
HELIOS does not generate itself. Constructed (not a real-world snapshot) to
keep regression coverage for [issue #89](https://github.com/solectrus/helios/issues/89)
after `real_world/user6` became an import-rejection case (it also ships
foreign services HELIOS no longer accepts).

## Highlights

- **External Traefik adopted as managed reverse proxy.** Custom entrypoints
  (`websecure` plus an extra `influxdb:8086`), a non-default resolver name
  `myresolver`, ACME email `postmaster@example.com`, a `./letsencrypt` volume,
  `restart: always`, and a dashboard router named `app-solectrus` (not
  `dashboard`). `ReverseProxyExtractor` adopts it, extracts the host
  `solectrus.example.com`, and captures `command`, `ports`, `volumes`,
  `restart`, `environment` verbatim into `reverse_proxy.*`. `Traefik.enabled?`
  returns `true` and `FORCE_SSL=true` follows automatically.
- **`influxdb` routing rewritten by HELIOS.** The donor routes InfluxDB with
  an `influxdb-solectrus` router on the custom `influxdb` entrypoint. HELIOS
  owns the routers of its own services, so it writes its own `influxdb`
  router against the same entrypoint and reads `myresolver` off the adopted
  command. The router is also what tells the import that InfluxDB is
  reachable, so `influxdb.publish_port: true` follows.
- **Every Traefik label is one HELIOS writes again**, so the stack passes
  `Import::CompatibilityCheck#unsupported_routing`. A middleware HELIOS does
  not know, or a router at another address, is refused instead.
- **Only baseline services** (`dashboard`, `influxdb`, `postgresql`, `redis`)
  behind Traefik — no collectors, no foreign services, so the stack passes
  `Import::CompatibilityCheck`.
