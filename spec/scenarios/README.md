# Scenarios

A scenario is one configuration of HELIOS, recorded end to end. It holds the
state HELIOS starts from and the stack HELIOS must produce from it. Each
family starts at a different point, and all of them end at the same pair of
files, the `compose.yaml` and the `.env` that HELIOS writes.

| Family    | Starts at                           | Covers                                  |
| --------- | ----------------------------------- | --------------------------------------- |
| `import/` | a foreign stack                     | adopting a stack HELIOS did not write   |
| `export/` | a `config.yaml` of an older release | the migration chain against a real file |

Each family is a directory with its own spec, and each scenario in it is a
directory again:

```
<family>/
├── README.md             where the input of this family comes from
├── <family>_spec.rb
└── <name>/
    ├── README.md         what this scenario is, and why it is worth keeping
    ├── input/            what HELIOS starts from
    └── snapshot/         what HELIOS must produce
        ├── helios/config.yaml
        ├── compose.yaml
        └── .env
```

## Input and snapshot

The split is the point of the layout. `input/` is written by hand and read as
intent: it says what this scenario is about, and a change to it is a decision.
`snapshot/` is written by HELIOS and read as consequence: it says what HELIOS
does today, and a change to it is the result of a decision made elsewhere.

A `snapshot/` is laid out like the data directory of a real host, so you can
copy one onto a machine and start it with `docker compose up -d`.

## Running and recording

```bash
bin/rspec spec/scenarios                      # compare against the snapshots
bin/rspec spec/scenarios/import               # one family
UPDATE_SNAPSHOTS=1 bin/rspec spec/scenarios   # write the snapshots anew
```

Record a snapshot whenever a change to the config schema or to the export is
meant to move the output. Then read the diff: every line in it must be a line
you wanted. Keep the diff small, because a scenario that changes for no reason
is a scenario nobody reads.

There is no second command that builds the snapshots. The recording happens
inside the example, so a snapshot holds exactly what the spec ran.

## Adding a scenario

1. Create `<family>/<name>/input/` with the files the family starts from, and
   an empty `<family>/<name>/snapshot/` next to it. A directory without a
   `snapshot/` is input alone (see below) and no spec runs it.
2. Run `UPDATE_SNAPSHOTS=1 bin/rspec spec/scenarios/<family>`.
3. Read the three files it wrote. Every value must be one the input asked for,
   or a default HELIOS is right to apply.
4. Write the `README.md` of the scenario. Say what makes it different from the
   scenarios that are already there.

The family README says where the input of that family comes from.

## Directories without a snapshot

A few directories under `import/` carry `input/` alone. Their donor stacks are
a corpus that other specs read, and no stack of ours comes out of them:
`minimal` feeds the compose and env parser specs, `real_world/user2` and
`real_world/user6` are stacks that `Import::CompatibilityCheck` must refuse.
