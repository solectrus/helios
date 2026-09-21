# export

A `config.yaml` taken from a running HELIOS instance, usually on an older
schema. `input/config.yaml` holds it, and `export_spec.rb` runs the pipeline:

    input/config.yaml  →  Migrate  →  snapshot/helios/config.yaml
                                   →  Export  →  snapshot/compose.yaml + .env

Two things the import family cannot cover:

1. The `ConfigurationMigrations` chain runs against a real file. Every
   `config.yaml` under `import/` carries the current schema version, because
   the importer produces it. A donated file carries the version of the HELIOS
   release that wrote it.
2. The export runs against a configuration that a released version already
   turned into a stack. If the donor also sends the `compose.yaml` and the
   `.env` of that stack, you can compare the two outputs once and see every
   change the export made since that release.

## Where the files come from

A HELIOS support bundle (Settings, Support) holds all three files. The bundle
masks passwords, tokens and coordinates, but it leaves the domain, the Let's
Encrypt email address and the Shelly device IDs in clear text. Replace those
by hand before you commit the scenario.

## Adding a scenario

Follow the steps in the `README.md` next to this one. For step 3, compare the
generated files against the ones in the bundle. Every difference is either an
intended change since the release of the donor, or a bug. Record the result
in the `README.md` of the scenario.
