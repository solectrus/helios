#!/usr/bin/env bash
# Stop hook: batched linting + typecheck of files touched during this turn.
# Groups paths by extension, invokes each tool once with its full file list,
# runs tsc if any .ts changed. Collects failures across tools and reports them
# all at once via exit 2 (which feeds the message back to Claude).
set -uo pipefail

input=$(cat)
stop_hook_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
session_id=$(printf '%s' "$input" | jq -r '.session_id // "default"')
marker="/tmp/helios-changed-files-$session_id"

# Loop guard: a previous Stop already ran the checks — let Claude finish.
if [[ "$stop_hook_active" == "true" ]]; then
  rm -f "$marker"
  exit 0
fi

[[ -f "$marker" ]] || exit 0

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" || exit 1

erb_files=()
ruby_files=()
ts_files=()
js_files=()
sh_files=()
pretty_files=()

# Keep the patterns in sync with track-changed-file.sh. `.mts`/`.mjs` land in
# js_files only: tsconfig covers app/frontend and app/components, not the root
# build configs, so there is nothing for tsc to check in them.
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  case "$f" in
    *.erb) erb_files+=("$f") ;;
    *.rb | *.rake | *.ru | */Gemfile | */Rakefile) ruby_files+=("$f") ;;
    *.ts)
      ts_files+=("$f")
      js_files+=("$f")
      ;;
    *.js | *.mjs | *.mts) js_files+=("$f") ;;
    *.sh) sh_files+=("$f") ;;
    *.json | *.yml | *.yaml | *.md | *.css) pretty_files+=("$f") ;;
  esac
done < <(sort -u "$marker")

rm -f "$marker"

failures=""

run_check() {
  local label="$1"
  shift
  local out
  if ! out=$("$@" 2>&1); then
    failures+="--- $label ---"$'\n'"$out"$'\n\n'
  fi
}

if [[ ${#erb_files[@]} -gt 0 ]]; then
  run_check "erb-format" bun run erb:format "${erb_files[@]}"
  run_check "herb-lint" bin/herb lint "${erb_files[@]}"
fi

[[ ${#ruby_files[@]} -gt 0 ]] && run_check "rubocop" bin/rubocop --autocorrect --force-exclusion "${ruby_files[@]}"
[[ ${#js_files[@]} -gt 0 ]] && run_check "eslint" bunx eslint --fix --no-warn-ignored "${js_files[@]}"
[[ ${#pretty_files[@]} -gt 0 ]] && run_check "prettier" bunx prettier --write --ignore-unknown "${pretty_files[@]}"

# Skip quietly when shellcheck (installed via the Brewfile) is unavailable.
# Note: a comment must not start with the tool's name — that reads as a directive.
if [[ ${#sh_files[@]} -gt 0 ]] && command -v shellcheck > /dev/null; then
  run_check "shellcheck" shellcheck "${sh_files[@]}"
fi

# Project-wide typecheck only if a .ts file actually changed
[[ ${#ts_files[@]} -gt 0 ]] && run_check "tsc" bun run tsc

if [[ -n "$failures" ]]; then
  printf 'Linter/typecheck issues during stop hook:\n\n%s' "$failures" >&2
  exit 2
fi
