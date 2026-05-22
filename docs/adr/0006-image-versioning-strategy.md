# ADR-0006: Image Versioning Strategy

## Context

Docker images can be tagged in different ways:

- `latest` (always newest)
- Semantic version (`1.2.3`)
- Major version (`1`)
- Major.minor (`1.2`)

Different strategies have different trade-offs for stability vs. freshness.

## Decision

Use different strategies for own services vs. third-party services:

| Service Type       | Tag Strategy         | Example                              |
| ------------------ | -------------------- | ------------------------------------ |
| SOLECTRUS services | `latest`             | `ghcr.io/solectrus/solectrus:latest` |
| Third-party        | Major version pinned | `postgres:18-alpine`                 |

During development, some SOLECTRUS services may temporarily use the `develop` tag instead of `latest` to track the development branch. This is switched to `latest` before release.

## Consequences

**Positive:**

- Own services always get latest features and fixes
- Third-party services protected from breaking changes
- Minor/patch updates still apply to third-party
- Watchtower can update everything safely

**Negative:**

- Own services may receive breaking changes (acceptable, we control them)
- Major version bumps for third-party require manual intervention

**Image tags:**

| Service        | Image                                     |
| -------------- | ----------------------------------------- |
| Dashboard      | `ghcr.io/solectrus/solectrus:latest`      |
| HELIOS         | `ghcr.io/solectrus/helios:latest`         |
| Power-Splitter | `ghcr.io/solectrus/power-splitter:latest` |
| PostgreSQL     | `postgres:18-alpine`                      |
| Redis          | `redis:8-alpine`                          |
| InfluxDB       | `influxdb:2-alpine`                       |
| Watchtower     | `nickfedor/watchtower:latest`             |

## Sidecar Images

Backups and restores run short-lived sidecar containers that are **not** Compose services and so do not appear in the table above. Their tags are pinned in Ruby constants:

| Image            | Constant                      | Pin               | Rationale                                                                                                                           |
| ---------------- | ----------------------------- | ----------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `docker:cli`     | `BackupRunner::IMAGE`         | Major (`29-cli`)  | Third-party — major-pinned like the table above.                                                                                    |
| `amazon/aws-cli` | `BackupRepository::S3::IMAGE` | Exact (`2.34.52`) | Amazon publishes no major/minor tags, only full `MAJOR.MINOR.PATCH` — an exact pin is the closest equivalent to the major-pin rule. |

`docker:cli` is defined once (`BackupRunner::IMAGE`); `BackupRepository::External` and `Backup::ConnectionTest` reuse that constant. `amazon/aws-cli` is defined once (`BackupRepository::S3::IMAGE`). A bump is therefore a one-line change in each case.

### Verifying a bump

The backup adapters parse the sidecars' CLI output (aws-cli's `list-objects-v2` text format, busybox `tar -tvf`) and classify their error wording with regexes — a version bump can break this silently. Before raising a pin, run the integration suite, which exercises both images against a real S3-compatible server (MinIO) and a real Docker stack:

```bash
bin/rspec --tag integration
```

The relevant specs are `spec/integration/backup_repository/{s3,external}_spec.rb` and `spec/integration/backup_runner_s3_spec.rb`.
