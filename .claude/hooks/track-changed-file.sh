#!/usr/bin/env bash
# PostToolUse hook: record paths of files edited during the turn so the Stop
# hook can lint/format them in one batched run per tool.
set -euo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
session_id=$(printf '%s' "$input" | jq -r '.session_id // "default"')

[[ -n "$file_path" ]] || exit 0

case "$file_path" in
  *.html.erb | *.rb | *.ts | *.json | *.yml | *.yaml | *.md | *.css) ;;
  *) exit 0 ;;
esac

printf '%s\n' "$file_path" >> "/tmp/helios-changed-files-$session_id"
