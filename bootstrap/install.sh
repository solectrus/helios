#!/usr/bin/env bash
#
# HELIOS bootstrap installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/solectrus/helios/main/bootstrap/install.sh | bash
#
# Unattended (no TTY, e.g. Proxmox LXC helper or CI) — opt in via env vars:
#   HELIOS_ASSUME_YES=1      auto-confirm operational prompts (install Docker,
#                            continue below recommended specs)
#   HELIOS_ACCEPT_LICENSE=1  accept the license without prompting (kept
#                            separate from HELIOS_ASSUME_YES on purpose)
#   HELIOS_QUIET=1           silence docker compose pull/up output
#
#   HELIOS_ASSUME_YES=1 HELIOS_ACCEPT_LICENSE=1 \
#     bash <(curl -fsSL https://raw.githubusercontent.com/solectrus/helios/main/bootstrap/install.sh)
#
# Detects whether the current directory already contains a SOLECTRUS stack
# (compose.yaml + .env) and either:
#   - performs a FRESH install (creates compose.yaml + .env from scratch), or
#   - ADDS HELIOS to the existing stack (patches compose.yaml in place).
#
# Note: no backup of compose.yaml is made here — HELIOS itself writes
# compose.yaml.bak and .env.bak before its first import.

set -euo pipefail

HELIOS_IMAGE="${HELIOS_IMAGE:-ghcr.io/solectrus/helios:latest}"
ENV_FILE=".env"
PROJECT_NAME="solectrus"

# GitHub repo + branch the installer was published from. Used to fetch the
# script's last-update timestamp from the GitHub API on welcome.
HELIOS_REPO="${HELIOS_REPO:-solectrus/helios}"
HELIOS_REF="${HELIOS_REF:-main}"

# Non-interactive opt-ins for unattended runs (Proxmox LXC helper, CI, …).
# HELIOS_ASSUME_YES auto-confirms the operational prompts (install Docker,
# continue below recommended specs). HELIOS_ACCEPT_LICENSE accepts the
# license — kept deliberately separate from HELIOS_ASSUME_YES so the legal
# consent is never granted implicitly. HELIOS_QUIET silences the docker
# compose pull/up output.
HELIOS_ASSUME_YES="${HELIOS_ASSUME_YES:-0}"
HELIOS_ACCEPT_LICENSE="${HELIOS_ACCEPT_LICENSE:-0}"
HELIOS_QUIET="${HELIOS_QUIET:-0}"

# Truthy test for the opt-in env vars above. Accepts the usual on/yes/true
# spellings; anything else (including the 0 default) is treated as false.
is_true() {
  case "$1" in
    1|y|Y|yes|Yes|YES|true|TRUE) return 0 ;;
    *) return 1 ;;
  esac
}

# Preflight thresholds. ABORT = the install will fail without this.
# RECOMMENDED = it will work but the user runs out of headroom soon.
# Calibrated against a real-world stack on a 16 GB / 2 GiB Proxmox VM.
#
# Disk floor at 1 GB covers the HELIOS image (~250 MB on disk) plus
# log/DB headroom and a safety margin for Docker overhead. The 5 GB
# recommendation is the comfortable target for a full stack (Dashboard +
# Postgres + InfluxDB + Redis + Traefik + collectors) that pulls 3-4 GB
# of images on first start. Collector-only hosts sit comfortably between
# the two.
MIN_DISK_GB=1
RECOMMENDED_DISK_GB=5
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
# With HELIOS_ASSUME_YES set we skip the terminal entirely and auto-confirm,
# which is what makes the operational prompts (Docker install, warn_or_abort)
# usable on a TTY-less host.
prompt_yn() {
  if is_true "$HELIOS_ASSUME_YES"; then
    printf '%syes (non-interactive)\n' "$1"
    return 0
  fi
  [ -r /dev/tty ] \
    || die "No TTY available for confirmation. Set HELIOS_ASSUME_YES=1 for an unattended run."
  local reply
  printf '%s' "$1" > /dev/tty
  read -r reply < /dev/tty
  is_true "$reply"
}

# Read a free-form line from the controlling terminal (stdin is the piped
# script) and echo it to stdout for command substitution. Callers must only
# reach this on the interactive path — choose_target_dir gates on /dev/tty.
# Returns non-zero on EOF (Ctrl-D / closed tty) so the caller can stop asking
# instead of spinning on an endless stream of empty reads.
prompt_line() {
  local reply=""
  printf '%s' "$1" > /dev/tty
  read -r reply < /dev/tty || return 1
  printf '%s' "$reply"
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

banner() {
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
}

welcome() {
  banner
  bold "  Installing HELIOS — your SOLECTRUS configuration manager"
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
    • Install Docker if missing (via https://get.docker.com)
    • Create compose.yaml and .env, or extend an existing compose.yaml
      by adding HELIOS as a new service
    • Pull and start HELIOS, reachable at http://<host>:3999

  Recommended host: ≥ ${RECOMMENDED_DISK_GB} GB free disk, ≥ $((RECOMMENDED_RAM_MB / 1024)) GB RAM, Linux x86_64 or arm64
TEXT
  printf '\n'

  bold "  License"
  cat <<TEXT
  HELIOS is source-available proprietary software. The official Docker
  image may be used free of charge for non-commercial, personal purposes.
  Commercial use requires prior written permission.

  Full license terms:
TEXT
  highlight "    https://github.com/${HELIOS_REPO}/blob/${HELIOS_REF}/LICENSE.md"
  printf '\n'

  # License consent is deliberately NOT covered by HELIOS_ASSUME_YES — granting
  # legal consent implicitly would be wrong. It needs its own explicit opt-in.
  if is_true "$HELIOS_ACCEPT_LICENSE"; then
    success "  License accepted via HELIOS_ACCEPT_LICENSE."
  elif is_true "$HELIOS_ASSUME_YES" || [ ! -r /dev/tty ]; then
    # Unattended run, but no explicit license opt-in — refuse rather than
    # accept on the user's behalf.
    error "  License not accepted. Re-run with HELIOS_ACCEPT_LICENSE=1 to accept"
    error "  the license for an unattended install:"
    error "    https://github.com/${HELIOS_REPO}/blob/${HELIOS_REF}/LICENSE.md"
    die "License acceptance required."
  else
    prompt_yn "  Accept license terms and continue? [y/N] " \
      || { warn "  Aborted."; exit 0; }
  fi
  printf '\n'
}

# Free space in whole megabytes for the filesystem holding `path`. Uses
# `df -kP` (1024-byte blocks, POSIX format) so it parses identically on
# BSD and GNU userlands. Returns 0 on any failure so callers err on the
# safe side and treat unreadable paths as "out of space". Megabytes (not
# gigabytes) so a sub-GB disk reports a real "492 MB" instead of a
# misleading floored-to-"0 GB".
free_mb() {
  local path="$1" kb
  kb="$(df -kP "$path" 2>/dev/null | awk 'END {print $4}')"
  if [[ "$kb" =~ ^[0-9]+$ ]]; then
    printf '%d\n' $((kb / 1024))
  else
    printf '0\n'
  fi
}

# Human-friendly space label from whole megabytes: stays in MB below 1 GB
# (so a tiny disk reads "492 MB free", not "0 GB free"), switches to whole
# GB at or above 1 GB.
format_space() {
  local mb="$1"
  if [ "$mb" -lt 1024 ]; then
    printf '%d MB\n' "$mb"
  else
    printf '%d GB\n' $((mb / 1024))
  fi
}

# Where the daemon actually stores images and volumes. Asks Docker instead of
# assuming /var/lib/docker: on Synology DSM that path exists as an empty stub
# on the tiny system partition while the real root sits on /volume1/@docker,
# which made the check report "592 MB free" on a NAS with 200 GB available.
# Prints nothing and returns 1 when the answer is unusable here — the daemon
# may be remote or inside a VM (Docker Desktop), where the reported path says
# nothing about this host's filesystems.
docker_root_dir() {
  local dir
  dir="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)"
  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  printf '%s\n' "$dir"
}

# Two callsites, two thresholds:
#   - "fresh":    user starts from nothing; the next steps will likely pull a
#                 full stack (~3-4 GB of images: Dashboard, Postgres, InfluxDB,
#                 Redis, Traefik, collectors, Watchtower) plus log/DB volumes,
#                 so we recommend RECOMMENDED_DISK_GB.
#   - "existing": stack is already running, its images are already on disk
#                 and Docker is paid for; we only add the HELIOS image
#                 (~250 MB on disk) on top, so MIN_DISK_GB is enough.
# In both modes, falling below MIN_DISK_GB is a hard fail because the HELIOS
# image won't fit otherwise.
ensure_disk_space() {
  local mode="${1:-fresh}"
  local cwd_mb docker_mb docker_dir available path
  cwd_mb="$(free_mb "$(pwd)")"
  available="$cwd_mb"
  path="$(pwd)"

  # Docker's data root may sit on a different filesystem than $(pwd); when
  # it does and is tighter, use those numbers instead.
  docker_dir="$(docker_root_dir)" || docker_dir=""
  if [ -n "$docker_dir" ]; then
    docker_mb="$(free_mb "$docker_dir")"
    if [ "$docker_mb" -lt "$available" ]; then
      available="$docker_mb"
      path="$docker_dir"
    fi
  fi

  if [ "$available" -lt "$((MIN_DISK_GB * 1024))" ]; then
    error "  ✗ Disk: $(format_space "$available") free at ${path} (need ≥ ${MIN_DISK_GB} GB)"
    die "Free up disk space and retry."
  fi

  if [ "$mode" = "fresh" ] && [ "$available" -lt "$((RECOMMENDED_DISK_GB * 1024))" ]; then
    warn_or_abort "  ⚠ Disk: $(format_space "$available") free at ${path} (recommended ≥ ${RECOMMENDED_DISK_GB} GB)"
    return
  fi

  success "  ✓ Disk: $(format_space "$available") free at ${path}"
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

# Verify the Docker daemon is reachable with the current user's permissions.
# `docker` being on PATH (checked by ensure_docker) doesn't mean we can talk to
# the daemon: the user may not be in the 'docker' group, or the daemon may be
# down. Catch that here — before we write compose.yaml/.env — instead of failing
# later at `docker compose pull` with a raw "permission denied" on the socket.
ensure_docker_access() {
  if docker info >/dev/null 2>&1; then
    success "  ✓ Docker daemon reachable"
    return
  fi

  error "  ✗ Docker is installed but not reachable as user '$(id -un)'."

  # Most likely cause for a non-root user: not in the 'docker' group yet (the
  # default right after a fresh Docker install — group changes only apply on
  # next login). Otherwise the daemon simply isn't running.
  local in_docker_group=false
  case " $(id -Gn 2>/dev/null) " in *" docker "*) in_docker_group=true ;; esac

  if [ "$(id -u)" -ne 0 ] && [ "$in_docker_group" = false ]; then
    cat >&2 <<MSG

  Add the current user to the 'docker' group, then start a new login session
  (log out and back in, or reboot) and re-run this installer:

      sudo usermod -aG docker $(id -un)
MSG
  else
    cat >&2 <<MSG

  Is the Docker daemon running? Start it and re-run this installer:

      sudo systemctl start docker
MSG
  fi
  printf '\n' >&2
  die "Docker daemon not reachable."
}

# Verify the current directory is writable before we try to create compose.yaml
# and .env in it. A non-root user installing into a root-owned directory (the
# classic `sudo mkdir /opt/solectrus` then install as yourself) sails through
# every other preflight and then dies on a raw "compose.yaml: Permission denied"
# from the shell redirect in write_compose_fresh. Catch it here — before we
# touch anything — with an actionable message.
#
# We advise installing into a directory the user owns (e.g. ~/solectrus) rather
# than a root-owned one under /opt: the installer writes here as the current
# user, and HELIOS only needs Docker access (already verified by the preceding
# ensure_docker_access), not a root login.
ensure_writable_dir() {
  local probe
  if probe="$(mktemp ./.helios-write-test.XXXXXX 2>/dev/null)"; then
    rm -f "$probe"
    success "  ✓ Directory writable: $(pwd)"
    return
  fi

  local user
  user="$(id -un)"
  error "  ✗ Directory not writable as user '$user': $(pwd)"

  # Report the actual owner rather than guessing. Field 3 of `ls -ld` is the
  # owner name (or numeric UID if it has no passwd entry) on both GNU and BSD.
  # SC2012: `.` is a fixed entry, not a glob — no filename-parsing hazard here,
  # and `find -printf`/`stat` would sacrifice the GNU/BSD portability we keep.
  local owner
  # shellcheck disable=SC2012
  owner="$(ls -ld . 2>/dev/null | awk 'NR==1 {print $3}')"

  cat >&2 <<MSG

  The installer needs to create compose.yaml and .env here, but this
  directory is owned by '${owner:-another user}' and is not writable by your
  user '$user'.

  Install into a directory you own — no root needed. Your user already has
  Docker access, which is all HELIOS requires:

      mkdir ~/solectrus && cd ~/solectrus
      # then re-run the installer here
MSG
  printf '\n' >&2
  die "Installation directory not writable."
}

# Can the current user create or write into DIR *without sudo*? If DIR exists
# it must be a writable directory; otherwise its nearest existing ancestor must
# be writable and traversable. Used to flag infeasible menu choices up front so
# /opt/solectrus on a non-root host is visibly off-limits rather than failing
# later on a raw redirect. We never shell out to sudo: HELIOS needs Docker
# access, not a root login (see ensure_docker_access / ensure_writable_dir).
dir_creatable() {
  local d="$1" parent
  if [ -e "$d" ]; then
    [ -d "$d" ] && [ -w "$d" ]
    return
  fi
  # Walk up to the nearest existing ancestor with parameter expansion rather
  # than forking `dirname` per level. Stripping the last /segment off "/opt"
  # yields "", which we pin back to "/" so the loop terminates at the root.
  parent="${d%/*}"; parent="${parent:-/}"
  while [ ! -e "$parent" ]; do parent="${parent%/*}"; parent="${parent:-/}"; done
  [ -w "$parent" ] && [ -x "$parent" ]
}

# Print one row of the install-directory menu. Shows the number and path, a
# parenthetical note (e.g. "recommended", "current directory"), and — when the
# target can't be created without root — a clear "(unavailable)" flag instead,
# so the user sees why /opt/solectrus is off-limits on a non-root host.
dir_menu_line() {
  local n="$1" d="$2" note="$3"
  if ! dir_creatable "$d"; then
    dim "    $n) $d   (unavailable — needs root, and the installer never uses sudo)"
    return
  fi
  if [ "$note" = "recommended" ]; then
    highlight "    $n) $d   (recommended)"
  elif [ -n "$note" ]; then
    printf '    %s) %s   (%s)\n' "$n" "$d" "$note"
  else
    printf '    %s) %s\n' "$n" "$d"
  fi
}

# Accept a chosen directory or reject it with a clear reason. Refuses anything
# that would require root rather than silently failing downstream.
try_select_dir() {
  local d="$1"
  if dir_creatable "$d"; then
    TARGET_DIR="$d"
    return 0
  fi
  error "  ✗ Cannot create '$d' as user '$(id -un)' without root."
  warn  "    Choose a directory you own, or create it first with the right owner."
  return 1
}

# Print the working directory (compose.yaml location) of any *running* SOLECTRUS
# stack on this host, one per line, deduplicated. Identifies a stack by its
# container images (…solectrus/…) rather than the Compose project name: older
# SOLECTRUS installs often ship no `name:` in compose.yaml, so their project name
# is CWD-derived and unreliable, whereas the image family is a hard signal. Reads
# the working_dir label Docker Compose stamps on every container. Empty output
# when Docker is absent/unreachable or no such stack runs.
detect_running_solectrus_dir() {
  command -v docker >/dev/null 2>&1 || return 0
  docker ps --format '{{.Image}}|{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null \
    | awk -F'|' '$1 ~ /(^|\/)solectrus\// && $2 != "" { print $2 }' \
    | sort -u
}

# True when a HELIOS container is already running as part of the stack whose
# Compose working dir is DIR. Lets the adopt path short-circuit "already
# installed" instead of asking to add HELIOS to a stack that already has it.
# The image must be exactly …solectrus/helios (tag/digest allowed), so a
# sibling like solectrus/helios-foo wouldn't match.
helios_running_in_dir() {
  local dir="$1"
  command -v docker >/dev/null 2>&1 || return 1
  docker ps --format '{{.Image}}|{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null \
    | awk -F'|' -v d="$dir" \
        '$1 ~ /(^|\/)solectrus\/helios(:|@|$)/ && $2 == d { found = 1 } END { exit !found }'
}

# A SOLECTRUS stack is already running on this host (in the given working dir(s),
# newline-separated). Because the project name ('solectrus') and HELIOS port
# (3999) are fixed, a second parallel stack would collide on both — so the only
# valid outcomes are "adopt that stack" or "abort". We never offer a fresh
# install alongside it. Sets TARGET_DIR to the adopted directory, or exits.
adopt_running_stack() {
  local dirs="$1" count dir
  count="$(printf '%s\n' "$dirs" | grep -c .)"

  # More than one running stack is already a broken state (they share the fixed
  # project name). Can't pick for the user — point them at the directories.
  if [ "$count" -gt 1 ]; then
    error "  ✗ Multiple running SOLECTRUS stacks detected:"
    printf '%s\n' "$dirs" | while IFS= read -r d; do [ -n "$d" ] && error "      $d"; done
    die "Cannot pick automatically. cd into the intended stack directory and re-run."
  fi

  dir="$dirs"

  # Already standing in it → just continue here (no relocation needed).
  [ "$dir" = "$PWD" ] && { TARGET_DIR="$PWD"; return; }

  # The detected stack already runs HELIOS → nothing to adopt. Relocate silently
  # so main's "already installed" guard reports it and ensures it's up, instead
  # of misleadingly asking to "add" HELIOS to a stack that already has it.
  if helios_running_in_dir "$dir"; then
    TARGET_DIR="$dir"
    return
  fi

  warn "  A running SOLECTRUS stack was detected at:"
  highlight "      $dir"
  printf '\n'

  # Unattended: refuse to mutate a live stack without a human present. Adoption
  # rewrites someone's running compose.yaml, so it must happen interactively.
  if is_true "$HELIOS_ASSUME_YES" || [ ! -r /dev/tty ]; then
    error "  Refusing to modify a running stack unattended."
    die "cd into $dir and re-run interactively to add HELIOS to it."
  fi

  bold "  HELIOS will be added to this existing stack."
  printf '\n'
  prompt_yn "  Add HELIOS to the stack at $dir? [y/N] " \
    || { warn "  Aborted."; exit 0; }
  printf '\n'
  TARGET_DIR="$dir"
}

# Decide where to install and leave the result in TARGET_DIR. Order of
# precedence:
#   1. Current dir holds a stack → extend it in place (the deliberate "cd into
#      my stack, add HELIOS" flow); never relocate.
#   2. A SOLECTRUS stack already runs elsewhere → adopt it or abort (a second
#      parallel stack can't coexist with the fixed project name + port).
#   3. Non-interactive           → current directory (backward compatible).
#   4. Interactive fresh install → offer a fixed menu of sudo-free targets.
#      The default depends on privilege: root installs to /opt/solectrus (it
#      can create and own it without sudo), a normal user to ~/solectrus.
choose_target_dir() {
  if detect_compose_file >/dev/null 2>&1 || [ -e "$ENV_FILE" ]; then
    TARGET_DIR="$PWD"
    return
  fi

  local running_dirs
  running_dirs="$(detect_running_solectrus_dir)"
  if [ -n "$running_dirs" ]; then
    adopt_running_stack "$running_dirs"
    return
  fi

  if is_true "$HELIOS_ASSUME_YES" || [ ! -r /dev/tty ]; then
    TARGET_DIR="$PWD"
    return
  fi

  # ${HOME:-/root}: an interactive installer always has HOME, but the fallback
  # keeps `set -u` from aborting here in a pathological env where it is unset.
  # Root can create+own /opt/solectrus sudo-free, so it's the root default; a
  # normal user defaults to ~/solectrus. Mark only the default as recommended.
  local d1="/opt/solectrus" d2="${HOME:-/root}/solectrus" d3="$PWD"
  local default rec1="" rec2=""
  if [ "$(id -u)" -eq 0 ]; then default=1; rec1="recommended"; else default=2; rec2="recommended"; fi

  bold "  Where should HELIOS be installed?"
  printf '\n'
  dir_menu_line 1 "$d1" "$rec1"
  dir_menu_line 2 "$d2" "$rec2"
  dir_menu_line 3 "$d3" "current directory"
  printf '\n'
  # No free-form path entry on purpose: to install elsewhere (e.g. a larger or
  # dedicated data disk — the stack's bind mounts incl. the InfluxDB database
  # live next to compose.yaml, ADR-0003), the user creates that directory,
  # cd's into it, and re-runs — it then appears here as the current directory.
  dim "  To install elsewhere (e.g. a larger or dedicated data disk), create the"
  dim "  directory, cd into it, and re-run — it appears here as current directory."
  printf '\n'

  local choice eof
  while :; do
    eof=0
    choice="$(prompt_line "  Choice [$default]: ")" || eof=1
    choice="${choice:-$default}"
    case "$choice" in
      1) try_select_dir "$d1" && break ;;
      2) try_select_dir "$d2" && break ;;
      3) try_select_dir "$d3" && break ;;
      *) warn "  Please enter 1, 2, or 3." ;;
    esac
    # On EOF we can't re-prompt; if the (default) target was rejected above,
    # abort cleanly instead of looping forever on an empty stream.
    [ "$eof" -eq 1 ] && die "No usable install directory selected. Create a directory you own, cd into it, and re-run."
  done
  printf '\n'
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
      - TZ
      - ADMIN_PASSWORD
      - SECRET_KEY_BASE
    volumes:
      - .:/data
      - /var/run/docker.sock:/var/run/docker.sock
      - /sys/fs/cgroup:/host/sys/fs/cgroup:ro
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

# Derive a stable ADMIN_PASSWORD from the existing SECRET_KEY_BASE. Mirrors
# HELIOS' own ConfigSchema::SYSTEM_DEFAULTS so both the install-time
# backfill (here) and any later HELIOS-side ensure_defaults! converge on the
# same value. Reproducible across re-runs (no churn in .env) and keeps the
# password unpredictable to anyone who doesn't already have read access to
# the SECRET_KEY_BASE.
derive_admin_password() {
  local secret hash
  secret="$(grep -E '^SECRET_KEY_BASE=' "$ENV_FILE" | head -n1 | cut -d= -f2-)"
  hash="$(printf '%s' "$secret" | shasum -a 256 | awk '{print $1}')"
  printf '%s\n' "${hash:0:32}"
}

# Backfill SECRET_KEY_BASE and ADMIN_PASSWORD in an existing .env. Order
# matters: SECRET_KEY_BASE is the input to derive_admin_password, so we
# always ensure it exists before deriving the password.
#
# Without SECRET_KEY_BASE the helios container can't boot. Without
# ADMIN_PASSWORD, the SOLECTRUS dashboard still starts but its admin actions
# (editing settings, prices, etc.) are inaccessible — worse than picking a
# derived value. Sets GENERATED_ADMIN_PASSWORD when a new password was
# created so the caller can show it to the user (otherwise it would only
# live in .env, undiscovered).
ensure_helios_secrets() {
  GENERATED_ADMIN_PASSWORD=""
  grep -qE '^SECRET_KEY_BASE=.+' "$ENV_FILE" \
    || printf 'SECRET_KEY_BASE=%s\n' "$(generate_secret)" >> "$ENV_FILE"
  if ! grep -qE '^ADMIN_PASSWORD=.+' "$ENV_FILE"; then
    GENERATED_ADMIN_PASSWORD="$(derive_admin_password)"
    printf 'ADMIN_PASSWORD=%s\n' "$GENERATED_ADMIN_PASSWORD" >> "$ENV_FILE"
  fi
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

# True when the helios container is actually up for this stack. Declaring the
# service in compose.yaml (helios_service_present) does NOT mean it is running,
# so the "already installed" branches consult this before claiming a reachable
# URL. `docker compose ps -q` lists only running containers (no --all).
helios_running() {
  [ -n "$(docker compose -f "$COMPOSE_FILE" ps -q helios 2>/dev/null)" ]
}

# For the already-installed branches: make sure HELIOS is actually up before
# pointing at its URL. Being declared in compose.yaml is not the same as
# running, so start the stack when it's down rather than leaving the user on a
# dead link. Only reachable after Docker access has been verified
# (ensure_docker_access), so start_stack can safely talk to the daemon.
ensure_helios_started() {
  if ! helios_running; then
    bold "  HELIOS is installed but not running — starting it..."
    start_stack
  fi
  success "  Visit HELIOS at $(helios_url)"
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

# Run a command, silencing its output when HELIOS_QUIET is set. Used for the
# verbose docker compose pull/up steps on unattended runs.
run_quiet() {
  if is_true "$HELIOS_QUIET"; then
    "$@" >/dev/null 2>&1
  else
    "$@"
  fi
}

# Poll HELIOS' health endpoint until it answers, so the success banner's URL
# actually works when the user opens it. `docker compose up -d` returns as soon
# as the container is *created*, but Rails needs a few seconds to boot — without
# this wait, opening the URL immediately yields a "connection refused" and reads
# as a failed install. We probe /up (Rails health check, served by
# Rails::HealthController, so no auth).
#
# We probe the very URL we advertise (helios_url), not the loopback, so the
# "up and reachable" we print matches what the user will actually open — a host
# that binds the port to one interface only would otherwise pass on localhost
# yet fail for the user. The loopback is used only when the host couldn't be
# determined (placeholder), where the advertised URL isn't pollable anyway.
#
# Best-effort: silently skipped when curl is absent, and on timeout we print a
# reassuring note rather than fail — a slow boot must never abort the install.
wait_for_helios() {
  command -v curl >/dev/null 2>&1 || return 0

  local base
  base="$(helios_url)"
  case "$base" in
    *'<your-host>'*) base="http://localhost:3999" ;;
  esac

  local url="${base}/up" i=0 max=60 tty=0
  [ -t 1 ] && tty=1

  [ "$tty" -eq 1 ] && printf '  Waiting for HELIOS to become reachable'
  while [ "$i" -lt "$max" ]; do
    if curl -fsS --max-time 2 -o /dev/null "$url" 2>/dev/null; then
      [ "$tty" -eq 1 ] && printf '\n'
      success "  HELIOS is up and reachable."
      return 0
    fi
    [ "$tty" -eq 1 ] && printf '.'
    sleep 1
    i=$((i + 1))
  done

  [ "$tty" -eq 1 ] && printf '\n'
  warn "  HELIOS is still starting; give it a few more seconds before opening the URL."
}

start_stack() {
  # The staged "Pulling…/Starting…" headers stay either way; only the verbose
  # docker compose progress is suppressed under HELIOS_QUIET (via run_quiet).
  bold "Pulling images..."
  run_quiet docker compose -f "$COMPOSE_FILE" pull

  bold "Starting stack..."
  run_quiet docker compose -f "$COMPOSE_FILE" up -d

  wait_for_helios
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

# Final success banner shown after a fresh install or a successful adoption.
# Pass the freshly-generated admin password as the only argument; omit the
# argument when an existing ADMIN_PASSWORD was reused (and therefore should
# not be echoed back to the user).
print_running_banner() {
  local password="${1:-}"
  if [ -n "$password" ]; then
    cat <<MSG

================================================================
  HELIOS is running at $(helios_url)
  Initial admin password:  ${password}
================================================================
Keep this password safe — it is also stored in $ENV_FILE
(key ADMIN_PASSWORD) on this host.
MSG
  else
    cat <<MSG

================================================================
  HELIOS is running at $(helios_url)
================================================================
MSG
  fi
}

# Add HELIOS to a stack that already exists in the current directory (a
# Compose file and/or .env are present). Patches compose.yaml in place,
# backfills the secrets, and starts the stack. Assumes preflight (Docker
# access, writable dir) has already run in main().
install_into_existing_stack() {
  bold "Existing stack detected — adding HELIOS"

  if [ -z "$COMPOSE_FILE" ]; then
    die "$ENV_FILE exists but no Compose file found (${COMPOSE_CANDIDATES[*]}). Refusing to guess."
  fi
  [ -e "$ENV_FILE" ] || die "$COMPOSE_FILE exists but $ENV_FILE is missing. Refusing to guess."

  if helios_service_present; then
    bold "HELIOS is already declared in $COMPOSE_FILE — nothing to add."
    ensure_helios_started
    return
  fi

  ensure_disk_space existing
  ensure_ram
  ensure_project_name
  append_helios_service
  ensure_helios_secrets

  success "$COMPOSE_FILE updated — added 'helios' service."
  start_stack

  print_running_banner "${GENERATED_ADMIN_PASSWORD:-}"
}

# Create a brand-new SOLECTRUS stack from scratch: a fresh compose.yaml + .env
# with a freshly generated admin password and SECRET_KEY_BASE, then start it.
install_fresh() {
  bold "No existing stack found — performing fresh install"

  ensure_disk_space fresh
  ensure_ram

  COMPOSE_FILE="${COMPOSE_CANDIDATES[0]}"

  local password secret
  password="$(generate_password)"
  secret="$(generate_secret)"

  write_compose_fresh
  write_env_fresh "$password" "$secret"

  success "Created $COMPOSE_FILE and $ENV_FILE."
  start_stack

  print_running_banner "$password"
}

main() {
  COMPOSE_FILE="$(detect_compose_file)" || COMPOSE_FILE=""

  # Short-circuit when HELIOS is already installed AND running, before showing
  # the welcome banner — otherwise we'd ask "Continue?" only to immediately tell
  # the user there's nothing to do. A declared-but-stopped stack deliberately
  # falls through to the normal flow, where (after Docker access is verified)
  # the existing-stack branch starts it. Requires docker, so a missing-docker
  # edge case also falls through and is caught by the inner check below.
  if [ -n "$COMPOSE_FILE" ] && command -v docker >/dev/null 2>&1 \
     && helios_service_present && helios_running; then
    banner
    bold "  HELIOS is already installed and running."
    success "  Visit HELIOS at $(helios_url)"
    printf '\n'
    return
  fi

  welcome
  ensure_docker
  ensure_docker_access

  # Pick the install directory (only now, after Docker access is proven — the
  # only privilege HELIOS needs). This may relocate us into a fresh
  # ~/solectrus or /opt/solectrus, or into the working dir of a SOLECTRUS stack
  # already running on this host, so re-detect any existing stack afterwards.
  choose_target_dir
  if [ "$TARGET_DIR" != "$PWD" ]; then
    mkdir -p "$TARGET_DIR" || die "Could not create directory: $TARGET_DIR"
    cd "$TARGET_DIR" || die "Could not enter directory: $TARGET_DIR"
    COMPOSE_FILE="$(detect_compose_file)" || COMPOSE_FILE=""

    # The chosen directory may already run HELIOS (idempotent re-run into it).
    if [ -n "$COMPOSE_FILE" ] && helios_service_present; then
      success "  HELIOS is already installed in $(pwd)."
      ensure_helios_started
      printf '\n'
      return
    fi
  fi
  success "  HELIOS will be installed into: $(pwd)"
  printf '\n'

  ensure_writable_dir

  # Two install modes: extend an existing stack in place, or create one from
  # scratch. The branch selection stays here; the bodies live in their own
  # functions above.
  if [ -n "$COMPOSE_FILE" ] || [ -e "$ENV_FILE" ]; then
    install_into_existing_stack
  else
    install_fresh
  fi
}

# Run main unless we are being sourced (e.g. by bats tests in spec/bats/bootstrap/).
# Three invocations to consider:
#   bash install.sh      → BASH_SOURCE[0]=install.sh, $0=install.sh   → run
#   curl … | bash        → BASH_SOURCE[0]=<unset>,    $0=bash         → run
#   source install.sh    → BASH_SOURCE[0]=install.sh, $0=<caller>     → skip
if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
