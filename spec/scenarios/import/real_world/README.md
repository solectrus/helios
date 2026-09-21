# real_world scenarios

Anonymized snapshots of `compose.yaml` + `.env` from actual SOLECTRUS users
in the wild. Each subdirectory is one user (`user1`, `user2`, …) and runs
through the same round-trip test as the synthetic scenarios above:

    <compose>.bak + .env.bak  →  Import  →  config.yaml
    config.yaml               →  Export  →  compose.yaml + .env

Unlike the curated synthetic scenarios, these are deliberately messy —
commented-out alternatives, typos, inline literals, legacy variable names,
inconsistent measurements — and exist to keep the importer honest against
what people actually run in production.

A few snapshots ship only the donor `.bak` files and no `config.yaml`: their
stacks are refused by `Import::CompatibilityCheck` (foreign service images
HELIOS cannot reproduce), so there is no round-trip to verify. These are
exercised by `spec/services/import/compatibility_check_spec.rb` instead — see
each directory's own `README.md`.

## Adding a new user snapshot

1. Create `real_world/userN/` with the donor's anonymized `compose.yaml.bak`
   and `.env.bak` (strip hostnames, tokens, MAC addresses, locations).
2. Run `RAILS_ENV=test bin/rake 'fixtures:bootstrap[real_world/userN]'` to
   produce the expected `config.yaml`, `compose.yaml`, `.env`.
3. Add a `README.md` documenting which importer quirks the snapshot
   exercises, so future regressions point back to a real cause.
