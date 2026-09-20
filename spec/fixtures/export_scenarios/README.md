# export_scenarios

Each subdirectory holds a `config.yaml` taken from a running HELIOS
instance, plus the `compose.yaml` and `.env` that HELIOS must produce from
it. `spec/services/export_scenarios_spec.rb` runs the pipeline:

    helios/config.yaml.bak  →  Migrate  →  helios/config.yaml
    helios/config.yaml      →  Export   →  compose.yaml + .env

The scenarios in `import_scenarios/` start at a foreign stack and run the
importer. These start at a file HELIOS itself wrote, so they cover two
things the import scenarios cannot:

1. The `ConfigurationMigrations` chain runs against a real file. Every
   `config.yaml` under `import_scenarios/` carries the current schema
   version, because the importer produces it. A donated file carries the
   version of the HELIOS release that wrote it.
2. The export runs against a configuration that a released version already
   turned into a stack. If the donor also sends the `compose.yaml` and the
   `.env` of that stack, you can compare the two outputs once and see
   every change the export made since that release.

## Where the files come from

A HELIOS support bundle (Settings, Support) holds all three files. The
bundle masks passwords, tokens and coordinates, but it leaves the domain,
the Let's Encrypt email address and the Shelly device IDs in clear text.
Replace those by hand before you commit the scenario.

## Adding a new scenario

1. Create `export_scenarios/<name>/helios/config.yaml.bak` from the
   anonymized `config.yaml` of the donor.
2. Run `RAILS_ENV=test bin/rake fixtures:regenerate` to produce the
   expected `helios/config.yaml`, `compose.yaml` and `.env`.
3. Compare the generated files against the ones in the bundle. Every
   difference is either an intended change since the donor's release, or a
   bug. Record the result in the `README.md` of the scenario.
