#!/usr/bin/env bash
# PostToolUse hook: record paths of files edited during the turn so the Stop
# hook can lint/format them in one batched run per tool.
set -euo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
session_id=$(printf '%s' "$input" | jq -r '.session_id // "default"')

[[ -n "$file_path" ]] || exit 0

# Only track files inside the project. Scratchpad or temp files elsewhere have
# no linter config of their own and would fail the Stop hook for no reason.
[[ -z "${CLAUDE_PROJECT_DIR:-}" || "$file_path" == "$CLAUDE_PROJECT_DIR"/* ]] || exit 0

# Keep in sync with the bucket list in lint-on-stop.sh — a path recorded here
# but unmatched there (or vice versa) is silently never checked.
case "$file_path" in
  *.erb | *.rb | *.rake | *.ru | */Gemfile | */Rakefile) ;;
  *.ts | *.js | *.mjs | *.mts | *.sh) ;;
  *.json | *.yml | *.yaml | *.md | *.css) ;;
  *) exit 0 ;;
esac

printf '%s\n' "$file_path" >> "/tmp/helios-changed-files-$session_id"
