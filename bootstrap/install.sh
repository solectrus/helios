#!/usr/bin/env bash
#
# HELIOS bootstrap installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/solectrus/helios/develop/bootstrap/install.sh | bash
#
# Detects whether the current directory already contains a SOLECTRUS stack
# (compose.yaml + .env) and either:
#   - performs a FRESH install (creates compose.yaml + .env from scratch), or
#   - ADDS HELIOS to the existing stack (patches compose.yaml in place).
#
# Note: no backup of compose.yaml is made here — HELIOS itself writes
# compose.yaml.bak and .env.bak before its first import.

set -euo pipefail

HELIOS_IMAGE="${HELIOS_IMAGE:-ghcr.io/solectrus/helios:develop}"
ENV_FILE=".env"

# Docker Compose file name precedence (matches Compose CLI search order).
# First entry is the default when creating a fresh stack.
COMPOSE_CANDIDATES=(compose.yaml compose.yml docker-compose.yaml docker-compose.yml)

detect_compose_file() {
  local candidate
  for candidate in "${COMPOSE_CANDIDATES[@]}"; do
    if [ -e "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*" >&2; }
cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
dim()    { printf '\033[2m%s\033[0m\n' "$*"; }

clear_screen() {
  [ -t 1 ] || return 0
  if command -v tput >/dev/null 2>&1; then
    tput clear
  else
    printf '\033[2J\033[H'
  fi
}

die() { red "Error: $*"; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."; }

# stdin is the piped script, so read from the controlling terminal instead.
prompt_yn() {
  [ -r /dev/tty ] || die "No TTY available for confirmation."
  local reply
  printf '%s' "$1" > /dev/tty
  read -r reply < /dev/tty
  case "$reply" in
    y|Y|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

need openssl
need awk

welcome() {
  clear_screen
  printf '\n'
  cyan "  ███████╗ ██████╗ ██╗     ███████╗ ██████╗████████╗██████╗ ██╗   ██╗███████╗"
  cyan "  ██╔════╝██╔═══██╗██║     ██╔════╝██╔════╝╚══██╔══╝██╔══██╗██║   ██║██╔════╝"
  cyan "  ███████╗██║   ██║██║     █████╗  ██║        ██║   ██████╔╝██║   ██║███████╗"
  cyan "  ╚════██║██║   ██║██║     ██╔══╝  ██║        ██║   ██╔══██╗██║   ██║╚════██║"
  cyan "  ███████║╚██████╔╝███████╗███████╗╚██████╗   ██║   ██║  ██║╚██████╔╝███████║"
  cyan "  ╚══════╝ ╚═════╝ ╚══════╝╚══════╝ ╚═════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝"
  dim  "  https://solectrus.de                  Copyright © 2020-2026 Georg Ledermann"
  printf '\n'
  bold "  Installing HELIOS — knows your SOLECTRUS configuration better than you do"
  printf '\n'
  yellow "  ⚠  Developer preview — work in progress, for experienced users only."
  yellow "     Not recommended for production use yet."
  printf '\n'
  cat <<TEXT
  This installer will:
    • Install Docker if missing (Linux only, via https://get.docker.com)
    • Create compose.yaml and .env, or extend an existing compose.yaml
      by adding HELIOS as a new service
    • Pull and start HELIOS, reachable at http://<host>:3999

  Working directory: $(pwd)

TEXT

  prompt_yn "  Continue? [y/N] " || { yellow "  Aborted."; exit 0; }
  printf '\n'
}

ensure_docker() {
  command -v docker >/dev/null 2>&1 && return

  yellow "Docker is not installed."

  if [ "$(uname -s)" != "Linux" ]; then
    die "Install Docker manually: https://docs.docker.com/get-docker/"
  fi

  local sudo_cmd=""
  if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 \
      || die "Root or sudo required. Install Docker manually: https://docs.docker.com/get-docker/"
    sudo_cmd="sudo"
  fi

  need curl
  prompt_yn "Install Docker now via https://get.docker.com? [y/N] " \
    || die "Docker is required."

  bold "Installing Docker..."
  curl -fsSL https://get.docker.com | $sudo_cmd sh
  command -v docker >/dev/null 2>&1 || die "Docker installation failed."
  green "Docker installed."
}

generate_secret() { openssl rand -hex 64; }
generate_password() {
  # Avoid `head -c 32` here: it closes the pipe early and can make `tr` exit
  # with SIGPIPE, which `set -o pipefail` would catch as a failure.
  local raw
  raw="$(openssl rand -base64 48 | tr -d '=+/')"
  printf '%s\n' "${raw:0:32}"
}

# Single source of truth for the helios service YAML. Matches the canonical
# form that HELIOS's own Export::Compose generates (watchtower label + json-file
# logging), so a user's compose.yaml doesn't change on first HELIOS export.
helios_service_yaml() {
  cat <<YAML
  helios:
    image: ${HELIOS_IMAGE}
    environment:
      - ADMIN_PASSWORD
      - SECRET_KEY_BASE
    volumes:
      - .:/data
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - 3999:3000
    restart: unless-stopped
    labels:
      - com.centurylinklabs.watchtower.scope=solectrus
    logging:
      driver: json-file
      options:
        max-size: 10m
        max-file: '3'
YAML
}

write_compose_fresh() {
  {
    printf 'name: solectrus\n\nservices:\n'
    helios_service_yaml
  } > "$COMPOSE_FILE"
}

write_env_fresh() {
  local password="$1" secret="$2"
  # 0600: file holds plaintext admin password and SECRET_KEY_BASE
  (
    umask 077
    cat > "$ENV_FILE" <<ENV
ADMIN_PASSWORD=${password}
SECRET_KEY_BASE=${secret}
ENV
  )
}

# Backfill ADMIN_PASSWORD / SECRET_KEY_BASE in an existing .env. Collector-only
# stacks lack both — without SECRET_KEY_BASE the helios container can't boot.
ensure_helios_secrets() {
  grep -qE '^ADMIN_PASSWORD=.+' "$ENV_FILE" \
    || printf 'ADMIN_PASSWORD=%s\n' "$(generate_password)" >> "$ENV_FILE"
  grep -qE '^SECRET_KEY_BASE=.+' "$ENV_FILE" \
    || printf 'SECRET_KEY_BASE=%s\n' "$(generate_secret)" >> "$ENV_FILE"
}

ensure_project_name() {
  # Let `docker compose config` canonicalize the YAML so we don't have to
  # worry about quoting variants. The top-level `name:` is unindented;
  # nested names (e.g. networks.default.name) are indented, so `^name:`
  # picks the top-level one.
  local effective_name
  effective_name="$(
    docker compose -f "$COMPOSE_FILE" config 2>/dev/null \
      | awk '/^name:/ {print $2; exit}'
  )" || die "$COMPOSE_FILE could not be parsed by 'docker compose config'. Fix manually and re-run."

  # `docker compose config` always emits a name — either from the `name:` key
  # in the file, or falling back to the directory name. Grep the raw file to
  # tell those two cases apart.
  if grep -qE '^name:' "$COMPOSE_FILE"; then
    [ "$effective_name" = "solectrus" ] && return
    die "$COMPOSE_FILE has 'name: $effective_name' — HELIOS requires 'solectrus'. Fix manually and re-run."
  fi

  # No explicit `name:`. If the current (CWD-derived) name differs from
  # `solectrus`, stop the old project first — otherwise the upcoming rename
  # would orphan any running containers under the old project name.
  if [ "$effective_name" != "solectrus" ] \
     && [ -n "$(docker compose -f "$COMPOSE_FILE" ps -q 2>/dev/null)" ]; then
    bold "Renaming project '$effective_name' → 'solectrus'. Stopping old project..."
    docker compose -f "$COMPOSE_FILE" down
  fi

  # Prepend `name: solectrus` so the project name no longer depends on CWD.
  local tmp
  tmp="$(mktemp "./${COMPOSE_FILE}.XXXXXX")"
  {
    printf 'name: solectrus\n\n'
    cat "$COMPOSE_FILE"
  } > "$tmp"
  mv "$tmp" "$COMPOSE_FILE"
}

helios_service_present() {
  docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null \
    | grep -Fxq helios
}

append_helios_service() {
  # Splice the helios block in right after the `services:` line. Using
  # head/tail sidesteps awk's portability issues with multi-line -v values.
  local tmp line
  line="$(grep -nE '^services:[[:space:]]*$' "$COMPOSE_FILE" | head -1 | cut -d: -f1)"
  [ -n "$line" ] || die "Could not find a 'services:' block in $COMPOSE_FILE."
  tmp="$(mktemp "./${COMPOSE_FILE}.XXXXXX")"
  {
    head -n "$line" "$COMPOSE_FILE"
    helios_service_yaml
    tail -n "+$((line + 1))" "$COMPOSE_FILE"
  } > "$tmp"
  mv "$tmp" "$COMPOSE_FILE"
}

start_stack() {
  bold "Pulling images..."
  docker compose -f "$COMPOSE_FILE" pull

  bold "Starting stack..."
  docker compose -f "$COMPOSE_FILE" up -d
}

# Best-effort URL the user will open. Prefers the primary outbound IPv4
# (reachable from other machines on the same network); falls back to the
# machine's hostname, then to a generic placeholder.
helios_url() {
  local host=""
  if command -v ip >/dev/null 2>&1; then
    host="$(ip -4 route get 1.1.1.1 2>/dev/null \
      | awk '{for (i=1; i<=NF; i++) if ($i == "src") { print $(i+1); exit }}')"
  fi
  [ -n "$host" ] || host="$(hostname 2>/dev/null || true)"
  [ -n "$host" ] || host="<your-host>"
  printf 'http://%s:3999' "$host"
}

main() {
  welcome
  ensure_docker

  COMPOSE_FILE="$(detect_compose_file)" || COMPOSE_FILE=""

  if [ -n "$COMPOSE_FILE" ] || [ -e "$ENV_FILE" ]; then
    bold "Existing stack detected — adding HELIOS"

    if [ -z "$COMPOSE_FILE" ]; then
      die "$ENV_FILE exists but no Compose file found (${COMPOSE_CANDIDATES[*]}). Refusing to guess."
    fi
    [ -e "$ENV_FILE" ] || die "$COMPOSE_FILE exists but $ENV_FILE is missing. Refusing to guess."

    if helios_service_present; then
      yellow "HELIOS is already declared in $COMPOSE_FILE — nothing to do."
      green "Visit HELIOS at $(helios_url)"
      return
    fi

    ensure_project_name
    append_helios_service
    ensure_helios_secrets

    green "$COMPOSE_FILE updated — added 'helios' service."
    yellow "ADMIN_PASSWORD and SECRET_KEY_BASE live in $ENV_FILE."
    start_stack
    green "HELIOS is running at $(helios_url)"
    return
  fi

  bold "No existing stack found — performing fresh install"

  COMPOSE_FILE="${COMPOSE_CANDIDATES[0]}"

  local password secret
  password="$(generate_password)"
  secret="$(generate_secret)"

  write_compose_fresh
  write_env_fresh "$password" "$secret"

  green "Created $COMPOSE_FILE and $ENV_FILE."
  start_stack

  cat <<MSG

================================================================
  HELIOS is running at $(helios_url)
  Initial admin password:  ${password}
================================================================
Keep this password safe — it is also stored in $ENV_FILE
(key ADMIN_PASSWORD) on this host.
MSG
}

main "$@"
