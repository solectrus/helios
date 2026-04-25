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
PROJECT_NAME="solectrus"

# GitHub repo + branch the installer was published from. Used to fetch the
# script's last-update timestamp from the GitHub API on welcome.
HELIOS_REPO="${HELIOS_REPO:-solectrus/helios}"
HELIOS_REF="${HELIOS_REF:-develop}"

# Preflight thresholds. ABORT = the install will fail without this.
# RECOMMENDED = it will work but the user runs out of headroom soon.
# Calibrated against a real-world stack on a 16 GB / 2 GiB Proxmox VM.
MIN_DISK_GB=5
MIN_RAM_MB=1024
RECOMMENDED_RAM_MB=2048

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

ANSI_RESET=$'\033[0m'
ANSI_BOLD=$'\033[1m'
ANSI_DIM=$'\033[2m'
ANSI_RED=$'\033[31m'
ANSI_GREEN=$'\033[32m'
ANSI_YELLOW=$'\033[33m'
ANSI_CYAN=$'\033[36m'
ANSI_CLEAR_SCREEN=$'\033[2J\033[H'

paintln() { printf '%s%s%s\n' "$1" "$2" "$ANSI_RESET"; }

bold()      { paintln "$ANSI_BOLD"   "$*"; }
dim()       { paintln "$ANSI_DIM"    "$*"; }
success()   { paintln "$ANSI_GREEN"  "$*"; }
warn()      { paintln "$ANSI_YELLOW" "$*"; }
error()     { paintln "$ANSI_RED"    "$*" >&2; }
highlight() { paintln "$ANSI_CYAN"   "$*"; }

clear_screen() {
  [ -t 1 ] || return 0
  if command -v tput >/dev/null 2>&1; then
    tput clear
  else
    printf '%s' "$ANSI_CLEAR_SCREEN"
  fi
}

die() { error "Error: $*"; exit 1; }

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

# Soft-fail preflight: print a warning, ask for confirmation, abort cleanly
# on no. Used by the "below recommended threshold" branches in disk/RAM checks.
warn_or_abort() {
  warn "$1"
  prompt_yn "    Continue anyway? [y/N] " || { warn "Aborted."; exit 0; }
  printf '\n'
}

need openssl
need awk

# Best-effort: prints nothing on network failure, missing curl, or
# unparseable response so a flaky network can't stall the install — the
# welcome banner simply omits the line.
fetch_last_updated() {
  command -v curl >/dev/null 2>&1 || return 0
  local response iso
  response="$(
    curl -fsSL --max-time 3 \
      "https://api.github.com/repos/${HELIOS_REPO}/commits?path=bootstrap/install.sh&sha=${HELIOS_REF}&per_page=1" \
      2>/dev/null
  )" || return 0
  # GitHub returns both author.date and committer.date; we want the latter
  # so rebased commits show the rebase time, not the original authoring time.
  iso="$(printf '%s' "$response" \
    | awk -F'"' '/"committer":/{c=1} c && /"date":/ {print $4; exit}')"
  [ -n "$iso" ] || return 0

  # GNU `date -d` (Linux) parses the trailing Z natively; BSD `date` (macOS)
  # ignores it and treats the parsed time as local, so on macOS we parse
  # under TZ=UTC to get the correct epoch, then re-format in the host TZ.
  local formatted epoch
  formatted="$(date -d "$iso" +'%Y-%m-%d %H:%M %Z' 2>/dev/null)" || formatted=""
  if [ -z "$formatted" ]; then
    epoch="$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s 2>/dev/null)" || epoch=""
    if [ -n "$epoch" ]; then
      formatted="$(date -r "$epoch" +'%Y-%m-%d %H:%M %Z' 2>/dev/null)" || formatted=""
    fi
  fi

  if [ -n "$formatted" ]; then
    printf '%s\n' "$formatted"
    return 0
  fi

  printf '%s' "$iso" \
    | awk -F'[T:Z]' '{ printf "%s %s:%s UTC\n", $1, $2, $3 }'
}

welcome() {
  clear_screen
  printf '\n'
  highlight "  ███████╗ ██████╗ ██╗     ███████╗ ██████╗████████╗██████╗ ██╗   ██╗███████╗"
  highlight "  ██╔════╝██╔═══██╗██║     ██╔════╝██╔════╝╚══██╔══╝██╔══██╗██║   ██║██╔════╝"
  highlight "  ███████╗██║   ██║██║     █████╗  ██║        ██║   ██████╔╝██║   ██║███████╗"
  highlight "  ╚════██║██║   ██║██║     ██╔══╝  ██║        ██║   ██╔══██╗██║   ██║╚════██║"
  highlight "  ███████║╚██████╔╝███████╗███████╗╚██████╗   ██║   ██║  ██║╚██████╔╝███████║"
  highlight "  ╚══════╝ ╚═════╝ ╚══════╝╚══════╝ ╚═════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝"
  dim  "  https://solectrus.de                  Copyright © 2020-2026 Georg Ledermann"
  printf '\n'
  bold "  Installing HELIOS — your SOLECTRUS configuration manager"
  printf '\n'
  warn "  ⚠  Developer preview — work in progress, for experienced users only."
  warn "     Not recommended for production use yet."
  printf '\n'
  # Synchronous GitHub fetch (up to 3s). Placed here so the timestamp sits
  # next to the description of what the script does, rather than dangling
  # under "Working directory".
  local last_updated
  last_updated="$(fetch_last_updated)"
  if [ -n "$last_updated" ]; then
    printf '  Script last updated at: %s\n\n' "$last_updated"
  fi
  cat <<TEXT
  This installer will:
    • Install Docker if missing (Linux only, via https://get.docker.com)
    • Create compose.yaml and .env, or extend an existing compose.yaml
      by adding HELIOS as a new service
    • Pull and start HELIOS, reachable at http://<host>:3999

  Recommended host: ≥ ${MIN_DISK_GB} GB free disk, ≥ $((RECOMMENDED_RAM_MB / 1024)) GB RAM, Linux x86_64 or arm64

  HELIOS will be installed into:
TEXT
  highlight "    $(pwd)"
  printf '\n'
  prompt_yn "  Continue? [y/N] " || { warn "  Aborted."; exit 0; }
  printf '\n'
}

# Free space in whole gigabytes for the filesystem holding `path`. Uses
# `df -kP` (1024-byte blocks, POSIX format) so it parses identically on
# BSD and GNU userlands. Returns 0 on any failure so callers err on the
# safe side and treat unreadable paths as "out of space".
free_gb() {
  local path="$1" kb
  kb="$(df -kP "$path" 2>/dev/null | awk 'END {print $4}')"
  if [[ "$kb" =~ ^[0-9]+$ ]]; then
    printf '%d\n' $((kb / 1024 / 1024))
  else
    printf '0\n'
  fi
}

# A full SOLECTRUS stack pulls ~3-4 GB of images (Dashboard, HELIOS,
# Postgres, InfluxDB, Redis, Traefik, several collectors, Watchtower)
# plus log + DB volumes. Below MIN_DISK_GB the install fails mid-pull.
ensure_disk_space() {
  local cwd_gb docker_gb available path
  cwd_gb="$(free_gb "$(pwd)")"
  available="$cwd_gb"
  path="$(pwd)"

  # /var/lib/docker may sit on a different filesystem than $(pwd); when
  # it does and is tighter, use those numbers instead.
  if [ -d /var/lib/docker ]; then
    docker_gb="$(free_gb /var/lib/docker)"
    if [ "$docker_gb" -lt "$available" ]; then
      available="$docker_gb"
      path="/var/lib/docker"
    fi
  fi

  if [ "$available" -lt "$MIN_DISK_GB" ]; then
    error "  ✗ Disk: ${available} GB free at ${path} (need ≥ ${MIN_DISK_GB} GB)"
    die "Free up disk space and retry."
  fi

  success "  ✓ Disk: ${available} GB free at ${path}"
}

# Total RAM in whole megabytes. /proc/meminfo's MemTotal is reported
# in kibibytes; we divide to get MB and return 0 when /proc/meminfo is
# unreadable (e.g. on macOS), letting callers skip the check there.
total_ram_mb() {
  local kb
  kb="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null)"
  if [[ "$kb" =~ ^[0-9]+$ ]] && [ "$kb" -gt 0 ]; then
    printf '%d\n' $((kb / 1024))
  else
    printf '0\n'
  fi
}

# Below MIN_RAM_MB the Rails apps (HELIOS + Dashboard) get OOM-killed
# before the stack finishes booting.
ensure_ram() {
  local mb
  mb="$(total_ram_mb)"

  # 0 means we couldn't read /proc/meminfo at all — most likely macOS.
  # Skip rather than error out, since this script is Linux-targeted and
  # macOS users are doing local development against a remote daemon.
  [ "$mb" -gt 0 ] || return 0

  if [ "$mb" -lt "$MIN_RAM_MB" ]; then
    error "  ✗ RAM: ${mb} MB (need ≥ ${MIN_RAM_MB} MB)"
    die "Add more RAM and retry."
  fi

  if [ "$mb" -lt "$RECOMMENDED_RAM_MB" ]; then
    warn_or_abort "  ⚠ RAM: ${mb} MB (recommended ≥ ${RECOMMENDED_RAM_MB} MB)"
    return
  fi

  success "  ✓ RAM: ${mb} MB"
}

ensure_docker() {
  command -v docker >/dev/null 2>&1 && return

  warn "Docker is not installed."

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
  success "Docker installed."
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
    printf 'name: %s\n\nservices:\n' "$PROJECT_NAME"
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
    [ "$effective_name" = "$PROJECT_NAME" ] && return
    die "$COMPOSE_FILE has 'name: $effective_name' — HELIOS requires '$PROJECT_NAME'. Fix manually and re-run."
  fi

  # No explicit `name:`. If the current (CWD-derived) name differs, stop the
  # old project first — otherwise the upcoming rename would orphan any
  # running containers under the old project name.
  if [ "$effective_name" != "$PROJECT_NAME" ] \
     && [ -n "$(docker compose -f "$COMPOSE_FILE" ps -q 2>/dev/null)" ]; then
    bold "Renaming project '$effective_name' → '$PROJECT_NAME'. Stopping old project..."
    docker compose -f "$COMPOSE_FILE" down
  fi

  # Prepend `name:` so the project name no longer depends on CWD.
  local tmp
  tmp="$(mktemp "./${COMPOSE_FILE}.XXXXXX")"
  {
    printf 'name: %s\n\n' "$PROJECT_NAME"
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
  COMPOSE_FILE="$(detect_compose_file)" || COMPOSE_FILE=""

  # Short-circuit when HELIOS is already declared, before showing the welcome
  # banner — otherwise we'd ask "Continue?" only to immediately tell the user
  # there's nothing to do. Requires docker, so a missing-docker edge case
  # falls through to the normal flow (and is caught by the inner check below).
  if [ -n "$COMPOSE_FILE" ] && command -v docker >/dev/null 2>&1 \
     && helios_service_present; then
    warn "HELIOS is already declared in $COMPOSE_FILE — nothing to do."
    success "Visit HELIOS at $(helios_url)"
    return
  fi

  welcome
  ensure_docker

  if [ -n "$COMPOSE_FILE" ] || [ -e "$ENV_FILE" ]; then
    bold "Existing stack detected — adding HELIOS"

    if [ -z "$COMPOSE_FILE" ]; then
      die "$ENV_FILE exists but no Compose file found (${COMPOSE_CANDIDATES[*]}). Refusing to guess."
    fi
    [ -e "$ENV_FILE" ] || die "$COMPOSE_FILE exists but $ENV_FILE is missing. Refusing to guess."

    if helios_service_present; then
      warn "HELIOS is already declared in $COMPOSE_FILE — nothing to do."
      success "Visit HELIOS at $(helios_url)"
      return
    fi

    ensure_disk_space
    ensure_ram
    ensure_project_name
    append_helios_service
    ensure_helios_secrets

    success "$COMPOSE_FILE updated — added 'helios' service."
    warn "ADMIN_PASSWORD and SECRET_KEY_BASE live in $ENV_FILE."
    start_stack
    success "HELIOS is running at $(helios_url)"
    return
  fi

  bold "No existing stack found — performing fresh install"

  ensure_disk_space
  ensure_ram

  COMPOSE_FILE="${COMPOSE_CANDIDATES[0]}"

  local password secret
  password="$(generate_password)"
  secret="$(generate_secret)"

  write_compose_fresh
  write_env_fresh "$password" "$secret"

  success "Created $COMPOSE_FILE and $ENV_FILE."
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

# Run main unless we are being sourced (e.g. by bats tests in spec/bats/bootstrap/).
# Three invocations to consider:
#   bash install.sh      → BASH_SOURCE[0]=install.sh, $0=install.sh   → run
#   curl … | bash        → BASH_SOURCE[0]=<unset>,    $0=bash         → run
#   source install.sh    → BASH_SOURCE[0]=install.sh, $0=<caller>     → skip
if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
