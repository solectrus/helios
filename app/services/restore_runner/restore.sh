# shellcheck shell=bash
# Executed inside the docker:cli sidecar by RestoreRunner. The container runs
# Alpine `ash` (not bash); `shell=bash` is the closest dialect Shellcheck
# supports that allows `set -o pipefail`.
# Receives positional args via `sh -c '<this script>' _ <token> <filename>
# <host-data-path> <pg-data> <influx-data> <redis-data> <restart-after>
# <services> <compose-filename> <destination> <host-staging>
# <aws-cli-image> <s3-dir-uri>`. Positional args are passed by argv (not
# interpolated) so values with shell metacharacters are safe. SERVICES is
# a space-separated list of compose service names (excluding `helios`) —
# the HELIOS service itself must never be torn down by this script, since
# stopping our own container would kill the user's UI mid-restore.
# COMPOSE_FILENAME is the basename of the compose file on the host (e.g.
# `compose.yaml` or `compose.yml`); HELIOS supports both.

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
DESTINATION="${10}"
HOST_STAGING="${11}"
AWS_CLI_IMAGE="${12}"
S3_DIR_URI="${13}"

OUTPUT_DIR="/output"
WORK_DIR="$OUTPUT_DIR/.restore-work"
BACKUP_PATH="$OUTPUT_DIR/$BACKUP_FILENAME"
ERROR_PATH="$OUTPUT_DIR/restore-error.txt"
COMPOSE_PATH="$HOST_DATA_PATH/$COMPOSE_FILENAME"

inner_env="-e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION"
if [ -n "${AWS_ENDPOINT_URL:-}" ]; then
  inner_env="$inner_env -e AWS_ENDPOINT_URL"
fi

s3_transfer() {
  # $1: source URI or local path, $2: destination URI or local path.
  # shellcheck disable=SC2086
  docker run --rm -v "$HOST_STAGING:/work" $inner_env "$AWS_CLI_IMAGE" \
    s3 cp "$1" "$2"
}

fail() {
  echo "$1" > "$ERROR_PATH"
  rm -rf "$WORK_DIR"
  if [ "$DESTINATION" = "s3" ]; then
    error_basename="$(basename "$ERROR_PATH")"
    # Drop the local copy only once it is safely on S3 — otherwise an
    # unreachable destination would erase the failure without a trace.
    if s3_transfer "/work/$error_basename" "${S3_DIR_URI}restore-error.txt" 2>/dev/null; then
      rm -f "$ERROR_PATH"
    fi
    rm -f "$BACKUP_PATH"
  fi
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
rm -f "$ERROR_PATH"
mkdir -p "$WORK_DIR"

# For S3 destinations the tar is not present locally yet — pull it down
# into the staging dir via a nested aws-cli sidecar before validation
# starts. After a successful restore the local copy is removed so the
# staging dir does not accumulate archives across runs.
if [ "$DESTINATION" = "s3" ]; then
  rm -f "$BACKUP_PATH"
  s3_transfer "${S3_DIR_URI}${BACKUP_FILENAME}" "/work/${BACKUP_FILENAME}" \
    || fail "S3 download failed"
fi

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

DB_START_LOG="$WORK_DIR/compose-db-up.log"
if ! compose up --no-build --wait -d postgresql influxdb > "$DB_START_LOG" 2>&1; then
  fail "Failed to start database services: $(tail -n 20 "$DB_START_LOG" | tr '\n' ' ')"
fi

POSTGRES_CONTAINER="$(compose ps -q postgresql)"
INFLUXDB_CONTAINER="$(compose ps -q influxdb)"
[ -n "$POSTGRES_CONTAINER" ] || fail "PostgreSQL container is missing after start"
[ -n "$INFLUXDB_CONTAINER" ] || fail "InfluxDB container is missing after start"

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

POSTGRES_RESTORE_LOG="$WORK_DIR/postgresql-restore.log"
if ! gunzip -c "$PG_FILE" \
  | docker exec -i "$POSTGRES_CONTAINER" \
      psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -U postgres --dbname=solectrus_production \
      > "$POSTGRES_RESTORE_LOG" 2>&1; then
  fail "PostgreSQL restore failed: $(tail -n 20 "$POSTGRES_RESTORE_LOG" | tr '\n' ' ')"
fi

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
  START_LOG="$WORK_DIR/compose-up.log"
  # See SERVICES note above for why this is unquoted.
  # shellcheck disable=SC2086
  if ! compose up --no-build -d $SERVICES > "$START_LOG" 2>&1; then
    fail "Failed to start restored stack: $(tail -n 20 "$START_LOG" | tr '\n' ' ')"
  fi
fi

rm -rf "$WORK_DIR"

if [ "$DESTINATION" = "s3" ]; then
  rm -f "$BACKUP_PATH"
fi
