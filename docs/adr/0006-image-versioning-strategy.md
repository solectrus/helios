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

Backups and restores run a short-lived sidecar container that is **not** a Compose service and so does not appear in the table above. Its tag is pinned in a Ruby constant:

| Image        | Constant              | Pin              | Rationale                                        |
| ------------ | --------------------- | ---------------- | ------------------------------------------------ |
| `docker:cli` | `BackupRunner::IMAGE` | Major (`29-cli`) | Third-party — major-pinned like the table above. |

`docker:cli` is defined once (`BackupRunner::IMAGE`); `BackupRepository::External` and `Backup::ConnectionTest` reuse that constant. A bump is therefore a one-line change.

S3 access has no sidecar image at all: HELIOS talks to S3 directly through the `aws-sdk-s3` gem, so its version moves with Bundler (`bundle update aws-sdk-s3`) like any other Ruby dependency.

### Verifying a bump

The backup adapter parses the sidecar's output (`tar -tvf`) and classifies its error wording with regexes — a version bump can break this silently. Before raising the pin, run the integration suite, which exercises the docker:cli image and the S3 adapter against a real S3-compatible server (MinIO):

```bash
bin/rspec --tag integration
```

The relevant specs are `spec/integration/backup_repository/{s3,external}_spec.rb` and `spec/integration/backup_runner_s3_spec.rb`.
