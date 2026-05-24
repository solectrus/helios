# shellcheck shell=bash
# Executed inside the docker:cli sidecar by RestoreRunner. The container runs
# Alpine `ash` (not bash); `shell=bash` is the closest dialect Shellcheck
# supports that allows `set -o pipefail`.
# Receives positional args via `sh -c '<this script>' _ <token> <filename>
# <host-data-path> <pg-data> <influx-data> <redis-data> <restart-after>
# <services> <compose-filename>`. Positional args are passed by argv (not
# interpolated) so values with shell metacharacters are safe. SERVICES is
# a space-separated list of compose service names (excluding `helios`) —
# the HELIOS service itself must never be torn down by this script, since
# stopping our own container would kill the user's UI mid-restore.
# COMPOSE_FILENAME is the basename of the compose file on the host (e.g.
# `compose.yaml` or `compose.yml`); HELIOS supports both.
#
# This script no longer talks to the backup destination directly: it
# expects the tar to be present in /output (the staging dir) already.
# For S3 destinations HELIOS fetches the tar via aws-sdk-s3 before
# launching the container; for local/external destinations the tar is
# served from its usual location through the same bind mount.

set -eu
set -o pipefail

TOKEN="$1"
BACKUP_FILENAME="$2"
HOST_DATA_PATH="$3"
POSTGRES_DATA_PATH="$4"
INFLUXDB_DATA_PATH="$5"
REDIS_DATA_PATH="$6"
RESTART_AFTER="$7"
SERVICES="$8"
COMPOSE_FILENAME="$9"

OUTPUT_DIR="/output"
WORK_DIR="$OUTPUT_DIR/.restore-work"
BACKUP_PATH="$OUTPUT_DIR/$BACKUP_FILENAME"
ERROR_PATH="$OUTPUT_DIR/restore-error.txt"
PHASE_PATH="$OUTPUT_DIR/restore-phase.txt"
COMPOSE_PATH="$HOST_DATA_PATH/$COMPOSE_FILENAME"

# Atomic write so RestoreRunner.current_phase never reads a half-written name.
set_phase() {
  printf '%s\n' "$1" > "$PHASE_PATH.tmp" && mv "$PHASE_PATH.tmp" "$PHASE_PATH"
}

fail() {
  echo "$1" > "$ERROR_PATH"
  rm -f "$PHASE_PATH"
  rm -rf "$WORK_DIR"
  exit 1
}

compose() {
  if [ -f "$HOST_DATA_PATH/.env" ]; then
    docker compose -f "$COMPOSE_PATH" --project-directory "$HOST_DATA_PATH" --env-file "$HOST_DATA_PATH/.env" --progress plain "$@"
  else
    docker compose -f "$COMPOSE_PATH" --project-directory "$HOST_DATA_PATH" --progress plain "$@"
  fi
}

rm -rf "$WORK_DIR"
rm -f "$ERROR_PATH" "$PHASE_PATH"
mkdir -p "$WORK_DIR"

set_phase extracting

[ -f "$BACKUP_PATH" ] || fail "Backup archive is missing"

tar -tf "$BACKUP_PATH" > "$WORK_DIR/entries.txt" || fail "Backup archive could not be read"
while IFS= read -r entry; do
  case "$entry" in
    /*|../*|*/../*) fail "Backup archive contains unsafe paths" ;;
  esac
done < "$WORK_DIR/entries.txt"

tar -xf "$BACKUP_PATH" -C "$WORK_DIR" || fail "Backup archive could not be extracted"

set -- "$WORK_DIR"/solectrus-postgresql-backup-*.sql.gz
[ -f "$1" ] || fail "PostgreSQL backup is missing"
PG_FILE="$1"

set -- "$WORK_DIR"/solectrus-influxdb-backup-*.tar.gz
[ -f "$1" ] || fail "InfluxDB backup is missing"
INFLUX_FILE="$1"

CONFIG_FILE="$WORK_DIR/helios/config.yaml"
[ -f "$CONFIG_FILE" ] || fail "HELIOS configuration is missing"

# `down -v` removes anonymous volumes. Required because InfluxDB's image
# declares `/etc/influxdb2` as a volume holding the CLI config; if that
# survives the wipe of the bind-mounted data dir, the next setup run
# aborts with `config name "default" already exists` and the entrypoint
# self-wipes bolt+engine in a restart loop.
set_phase stopping_services
STOP_LOG="$WORK_DIR/compose-down.log"
# Intentionally unquoted: SERVICES is a space-separated list of service
# names that must be word-split into individual `down` arguments. Compose
# service names cannot contain whitespace, so splitting is safe.
# shellcheck disable=SC2086
if ! compose down -v --remove-orphans $SERVICES > "$STOP_LOG" 2>&1; then
  fail "Failed to stop services before restore: $(tail -n 20 "$STOP_LOG" | tr '\n' ' ')"
fi

rm -rf "$POSTGRES_DATA_PATH" "$INFLUXDB_DATA_PATH" "$REDIS_DATA_PATH" \
  || fail "Failed to clear database directories"
mkdir -p "$POSTGRES_DATA_PATH" "$INFLUXDB_DATA_PATH" "$REDIS_DATA_PATH" \
  || fail "Failed to recreate database directories"

set_phase starting_databases
DB_START_LOG="$WORK_DIR/compose-db-up.log"
if ! compose up --no-build --wait -d postgresql influxdb > "$DB_START_LOG" 2>&1; then
  fail "Failed to start database services: $(tail -n 20 "$DB_START_LOG" | tr '\n' ' ')"
fi

POSTGRES_CONTAINER="$(compose ps -q postgresql)"
INFLUXDB_CONTAINER="$(compose ps -q influxdb)"
[ -n "$POSTGRES_CONTAINER" ] || fail "PostgreSQL container is missing after start"
[ -n "$INFLUXDB_CONTAINER" ] || fail "InfluxDB container is missing after start"

# On a fresh data dir the postgres image runs a bootstrap server that only
# listens on the Unix socket (`listen_addresses=''`). The compose healthcheck
# (`pg_isready -U postgres`, socket-based) can flip "healthy" against that
# throwaway server, so `compose up --wait` returns before TCP is open. Probe
# TCP directly until the production server is up — otherwise the first psql
# below races into "Connection refused". Mirrors
# orchestration/postgresql_upgrade.rb#wait_until_ready!.
PG_TCP_DEADLINE=$(( $(date +%s) + 120 ))
until docker exec "$POSTGRES_CONTAINER" pg_isready -h 127.0.0.1 -U postgres -q > /dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$PG_TCP_DEADLINE" ]; then
    fail "PostgreSQL did not accept TCP connections within 120 seconds"
  fi
  sleep 1
done

# The pg_dump archive expects database `solectrus_production`, but a fresh
# init only creates `POSTGRES_DB` (`solectrus`). On a normal stack SOLECTRUS
# creates the production DB on its first boot; during restore SOLECTRUS is
# not running yet, so create the target DB before importing.
POSTGRES_CREATE_LOG="$WORK_DIR/postgresql-createdb.log"
if ! docker exec "$POSTGRES_CONTAINER" \
       psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -U postgres -d postgres \
       -tAc "SELECT 1 FROM pg_database WHERE datname='solectrus_production'" \
       > "$POSTGRES_CREATE_LOG" 2>&1; then
  fail "Failed to query PostgreSQL: $(tail -n 20 "$POSTGRES_CREATE_LOG" | tr '\n' ' ')"
fi
if ! grep -q '^1$' "$POSTGRES_CREATE_LOG"; then
  if ! docker exec "$POSTGRES_CONTAINER" \
         psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -U postgres -d postgres \
         -c "CREATE DATABASE solectrus_production" \
         >> "$POSTGRES_CREATE_LOG" 2>&1; then
    fail "Failed to create solectrus_production: $(tail -n 20 "$POSTGRES_CREATE_LOG" | tr '\n' ' ')"
  fi
fi

set_phase restoring_postgres
POSTGRES_RESTORE_LOG="$WORK_DIR/postgresql-restore.log"
if ! gunzip -c "$PG_FILE" \
  | docker exec -i "$POSTGRES_CONTAINER" \
      psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -U postgres --dbname=solectrus_production \
      > "$POSTGRES_RESTORE_LOG" 2>&1; then
  fail "PostgreSQL restore failed: $(tail -n 20 "$POSTGRES_RESTORE_LOG" | tr '\n' ' ')"
fi

set_phase restoring_influx
INFLUX_RESTORE_LOG="$WORK_DIR/influx-restore.log"
if ! docker exec -i "$INFLUXDB_CONTAINER" sh -c '
  set -eu
  TOKEN="$1"
  ARCHIVE="/tmp/solectrus-influxdb-restore.tar.gz"
  WORK_PARENT="/tmp/solectrus-influxdb-restore"
  rm -rf "$WORK_PARENT" "$ARCHIVE"
  mkdir -p "$WORK_PARENT"
  trap "rm -rf $WORK_PARENT $ARCHIVE" EXIT
  cat > "$ARCHIVE"
  tar -xzf "$ARCHIVE" -C "$WORK_PARENT"
  set -- "$WORK_PARENT"/solectrus-influxdb-backup-*
  [ -d "$1" ]
  # --operator-token sets a known operator token after the restore.
  # Required when the backup was taken from an instance with hashed
  # tokens enabled (InfluxDB OSS 2.9+ default) — those backups contain
  # no plaintext operator token, so without this flag authentication
  # would break after --full overwrites the bolt. Harmless otherwise.
  influx restore --full --host http://localhost:8086 \
    -t "$TOKEN" --operator-token "$TOKEN" "$1"
' _ "$TOKEN" < "$INFLUX_FILE" > "$INFLUX_RESTORE_LOG" 2>&1; then
  fail "InfluxDB restore failed: $(tail -n 20 "$INFLUX_RESTORE_LOG" | tr '\n' ' ')"
fi

# If any service was stopped before the restore, leave the rest stopped —
# only the DBs (started fresh above for the import) keep running.
if [ "$RESTART_AFTER" = "1" ]; then
  set_phase starting_services
  START_LOG="$WORK_DIR/compose-up.log"
  # See SERVICES note above for why this is unquoted.
  # shellcheck disable=SC2086
  if ! compose up --no-build -d $SERVICES > "$START_LOG" 2>&1; then
    fail "Failed to start restored stack: $(tail -n 20 "$START_LOG" | tr '\n' ' ')"
  fi
fi

rm -f "$PHASE_PATH"
rm -rf "$WORK_DIR"
