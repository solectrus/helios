# import

A stack HELIOS did not write, adopted. `input/` holds the `compose.yaml` and
the `.env` of the donor, under whichever of the four names HELIOS accepts at
import time (see `Compose::FILENAMES`). `import_spec.rb` imports them and
exports the result again.

This is the widest family. The stacks under `real_world/` come from actual
SOLECTRUS users and cover configurations nobody would think to write by hand.
`real_world/README.md` says how one arrives here.

A donor may ship no `.env` at all and keep every value inline in the compose
file. `real_world/user17` is that case, and the importer has to read the
values out of the `environment:` lists.

Three directories carry `input/` alone, so no spec imports them. See the
`README.md` next to this one, under "Directories without a snapshot".
