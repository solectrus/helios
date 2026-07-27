---
description: Cut a HELIOS release via git-flow (start → finish → push → GitHub release)
argument-hint: <version>  e.g. 0.12.0
allowed-tools: Bash, Read, Write
---

Cut HELIOS release **$ARGUMENTS**.

No VERSION file exists — the version comes from git tags (`git describe` in
`config/application.rb`), so there is nothing to bump. Tooling: `git-flow-next` 1.1.0
(subcommands, not the classic script) and `gh`. Tags are `v`-prefixed and GPG-signed
automatically (`gitflow.release.finish.sign true`).

Stages 1–2 are local. **Never push before the Stage 3 gate.**

## Stage 1 — Validate & prepare

1. `VERSION` = `$ARGUMENTS` without leading `v`, `TAG=v$VERSION`. Not valid SemVer `X.Y.Z`
   or empty → stop, show correct form (`/release 0.12.0`).
2. Preconditions — abort with a clear message on failure:
   - on branch `develop`, working tree clean (`git status --porcelain`)
   - `git fetch origin` ok, `develop` not behind `origin/develop`
   - `$TAG` unused locally and remote (`git tag -l`, `git ls-remote --tags origin`)
   - `$VERSION` > `git tag --sort=-v:refname | head -1` (else stop and ask)
   - CI green on `develop` tip (`gh run list --branch develop --limit 1`); failed or still
     running → warn and ask
3. `bin/rake licenses:generate` — bundled license docs must match the shipped deps.
   Changes in `docs/legal` → show diff and commit on `develop` **before** the release branch
   as `chore(legal): refresh third-party licenses` (lands in this release and in the notes).
   No changes → continue. Task fails (`gh` unauthenticated, missing `node_modules`) → stop;
   never release with stale license docs.
4. Draft release notes from `git log $(git describe --tags --abbrev=0)..HEAD --no-merges`,
   matching the style of `gh release view <prev-tag>`:
   - short plain-language intro paragraph
   - `## Added` (`feat`), `## Improved` (`fix`/`perf`/`refactor`), `## Maintenance`
     (`chore`/`deps`/`docs`/`style`/`test`/`ci`); omit empty sections; collapse dependabot
     bumps into one line, e.g. _"Routine dependency updates and internal cleanup."_
   - written for users, not commit-log verbatim: group, drop noise, explain the _why_;
     **English**, matching history
   - write to `<scratchpad>/release-notes-$VERSION.md`, then show it inline

## Stage 2 — git-flow

History is **linear** (`main` and `develop` share the release commit) — every step is a
fast-forward, never create merge commits. Only after the notes draft exists:

5. `git flow release start $VERSION` (nothing to change on the branch — no version file)
6. `git flow release finish $VERSION -m "Tagging version $VERSION"` — merges to `main`,
   signs `$TAG`, deletes the branch. Never pass `--no-sign`. Remote-sync failure → report,
   retry with `-f` only after explaining why. Merge conflict → stop, hand back to the user.
7. `git checkout develop && git merge --ff-only main`. Not a clean fast-forward → stop and
   report. End on `develop`.

## Stage 3 — Push & publish (GATE)

8. Stop, summarize, wait for explicit approval: push `main`, `develop`, tag `$TAG`, create
   GitHub release for `$TAG` with the notes. Let the user edit the notes first.
9. Only on explicit "yes":
   - `git push origin main develop`
   - `git push origin $TAG`
   - `gh release create $TAG --title "$TAG" --notes-file <scratchpad>/release-notes-$VERSION.md`,
     then print the release URL

Declined at the gate → leave local state as-is (merges + tag exist), explain how to finish
manually. Do not undo.
