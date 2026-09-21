# setup

A new installation, answered screen by screen. `answers.yml` takes the place
of an `input/` directory, and `setup_spec.rb` runs the pipeline:

    answers.yml  →  Walk the surveys  →  payload
                 →  Save              →  snapshot/helios/config.yaml
                 →  Export            →  snapshot/compose.yaml + .env

The other two families start at a stack that already exists. These start at
an empty data directory, so they cover the one path the other two skip: the
answers of a user travel through the real controller. That makes four things
part of the result which no other scenario sees.

1. The real survey turns the answers into the payload.
   `spec/support/survey_walk.mjs` runs the survey-core Model over the survey
   that HELIOS serves, page by page, so the survey resolves its own
   `visibleIf`, fills in the defaults of the questions the answers leave
   alone, drops the values of the questions it never showed, and refuses a
   page it considers incomplete.
2. The payload goes through `SettingPersistence`. The UI-only answers drop
   out, and the borrowed fields go to the section that owns them.
3. Every side effect of a save happens: the SENEC sensors that one answer
   enables, the browser address that HELIOS adopts as `app_host`, and the
   export that each save triggers.
4. The order of the answers is the order of the screens. The survey of a later
   answer is shaped by the earlier ones, because `Surveys::Base#customize!`
   reads the configuration.

The stack does not start. `docker compose config` is the last word on the
output, and says whether Docker accepts the pair of files.

## Format of answers.yml

`browser_host` is the address the browser carries. HELIOS adopts it as
`app_host` on the first save, so it decides what the dashboard answers on.
It is optional and defaults to `helios.local`.

The outer `answers` is the list of saves, in the order the user makes them.
Each entry carries the `setting` (the survey ID in the URL), the inner
`answers` (what the user types or picks) and, for a sensor, its `name`.

Write only the answers a user gives. Leave out every question that keeps its
default, because the survey supplies those itself.

```yaml
browser_host: helios.local

answers:
  - setting: sensor
    name: inverter_power
    answers:
      source: senec
```

The walk refuses a scenario whose answers no longer fit the surveys, and the
message names the cause. An answer the survey has no question for reads
`asks for no question named obsolete_field`. A mandatory question that
nothing answers reads `stayed incomplete: host (Response required.)`.

The walk needs `bun` and the installed packages, which every place that runs
this suite has: `bin/ci` and the `ruby-tests` job on GitHub both install them.

## Starting state and secrets

The replay starts where `bootstrap/install.sh` leaves a real host: no
`config.yaml`, and `SECRET_KEY_BASE` plus `ADMIN_PASSWORD` in the
environment, which is how the compose file hands them to the helios service.
HELIOS therefore asks for the password from the first request on, so the
replay logs in before it answers anything. Both values are obvious dummies,
and the first save promotes them into `config.yaml`.

The database secrets are different. HELIOS mints one fresh random value per
installation, and `install.sh` cannot seed them. Pinning them would take the
minting out of the replay, so the replay lets it happen and replaces each
minted value by a `minted-*` placeholder afterwards. Replacement goes by
value, not by field: the four InfluxDB tokens carry one value, so one
placeholder reaches all four, and the snapshot still shows what the minting
decided.

## Adding a scenario

Follow the steps in the `README.md` next to this one. In place of an `input/`
directory, write `answers.yml`, and read the question names from the
`survey.json` of each setting under `app/services/surveys/`. A name that is
wrong stops the replay, so no name can go in unnoticed.
