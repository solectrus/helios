---
description: Cut a HELIOS release via git-flow (start → finish → push → GitHub release)
argument-hint: <version>  e.g. 0.12.0
allowed-tools: Bash, Read, Write
---

Cut a new HELIOS release for version **$ARGUMENTS**.

HELIOS has **no VERSION file** — the version lives entirely in git tags (`git describe`
in `config/application.rb`). So there is nothing to bump; the release is pure git-flow
plus a GitHub release. Tooling on this machine: `git-flow-next` 1.1.0 (subcommands, not
the classic script) and `gh`. Release tags are GPG-signed automatically
(`gitflow.release.finish.sign true`) and prefixed `v`.

Work in three stages. **Stages 1–2 are fully local. Never push until the user has
explicitly approved at the gate in Stage 3** (respects the global never-push rule).

## Stage 1 — Validate & prepare (local, read-only)

1. **Version.** Treat `$ARGUMENTS` as the version. Strip any leading `v`. If empty or not
   valid SemVer `X.Y.Z`, stop and tell the user the correct form (`/release 0.12.0`).
   Define `VERSION` (e.g. `0.12.0`) and `TAG=v$VERSION`.
2. **Preconditions** — run and abort with a clear message on any failure:
   - Current branch is `develop` (git-flow's release start point). If not, stop.
   - Working tree is clean (`git status --porcelain` empty).
   - `git fetch origin` succeeds and local `develop` is not behind `origin/develop`.
   - Tag `$TAG` does not already exist locally or on the remote (`git tag -l`,
     `git ls-remote --tags origin`).
   - `$VERSION` is greater than the latest existing tag (`git tag --sort=-v:refname | head -1`).
     If it isn't, stop and ask.
   - **CI is green** on the tip of `develop`: `gh run list --branch develop --limit 1`.
     If the latest run failed or is still running, warn and ask before continuing.
3. **Draft release notes.** Determine the previous tag (`git describe --tags --abbrev=0`)
   and read the commits to be released: `git log <prev-tag>..HEAD --no-merges --pretty=...`.
   For tone and structure, look at the last release with `gh release view <prev-tag>`.
   Produce notes in the **exact established style**:
   - A short plain-language **intro paragraph** explaining what the release is about.
   - Sections `## Added`, `## Improved`, `## Maintenance` (omit any that would be empty).
     Map conventional-commit types: `feat` → Added, `fix`/`perf`/`refactor` → Improved,
     `chore`/`deps`/`docs`/`style`/`test`/`ci` → Maintenance. Collapse the many dependabot
     bumps into a single line like _"Routine dependency updates and internal cleanup."_
   - Write for users, not commit-log verbatim: group related commits, drop noise, explain
     the _why_. German-project but release notes are **English** (matching history).
     Write the draft to the scratchpad (e.g. `<scratchpad>/release-notes-$VERSION.md`) so it
     survives, then show it to the user inline.

## Stage 2 — git-flow (local)

This mirrors the maintainer's established manual flow. The repo history is **linear** —
`main` and `develop` share the release commit, no merge bubbles — so every step below is a
fast-forward. Do not introduce artificial merge commits.

Only after the notes draft exists:

4. `git flow release start $VERSION` — creates `release/$VERSION` from `develop`.
   (No files to change on the release branch — HELIOS has no version file.)
5. `git flow release finish $VERSION -m "Tagging version $VERSION"` — merges the release
   into `main`, creates the signed tag `$TAG`, and deletes the release branch. The `-m`
   reproduces the existing tag-message style ("Tagging version X.Y.Z") and avoids the
   editor. Do **not** pass `--no-sign` (signing is intended).
   - If finish fails on a remote-sync check, report it; only retry with `-f` after telling
     the user why. If it stops on a merge conflict, stop and hand back to the user — do not
     improvise.
6. **Sync `develop` to the tagged `main`** (the maintainer's `git checkout develop &&
git merge main`): `git checkout develop` then `git merge --ff-only main`. This must be a
   clean fast-forward given the linear history; if it isn't, stop and report instead of
   creating a merge commit. End on `develop`.

## Stage 3 — Push & publish (GATE)

7. **Stop and summarize.** Show exactly what will happen and wait for explicit approval:
   - branches to push: `main`, `develop`
   - tag to push: `$TAG`
   - GitHub release to create for `$TAG` with the drafted notes
     Let the user edit the notes before approving.
8. **Only on explicit "yes":**
   - `git push origin main develop`
   - `git push origin $TAG`
   - `gh release create $TAG --title "$TAG" --notes-file <scratchpad>/release-notes-$VERSION.md`
     Then print the release URL from `gh`.

If the user declines at the gate, leave the local state as-is (merges + tag already exist
locally) and tell them how to finish manually later. Do not undo their work.
