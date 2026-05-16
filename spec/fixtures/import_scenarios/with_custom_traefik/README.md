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
- **Dashboard `test-ratelimit` middleware preserved.** HELIOS owns the
  dashboard's own router/entrypoints/tls labels, but routes the extra
  middleware labels into `service_overrides[dashboard].labels` (ADR-0015) so
  they re-emit after HELIOS's generated labels.
- **`influxdb` Traefik routing preserved.** The per-service `traefik.*` labels
  (`influxdb-solectrus` router on the custom `influxdb` entrypoint with
  `myresolver`) round-trip via `service_overrides[influxdb].labels`.
- **Only baseline services** (`dashboard`, `influxdb`, `postgresql`, `redis`)
  behind Traefik — no collectors, no foreign services, so the stack passes
  `Import::SupportedServicesCheck`.
