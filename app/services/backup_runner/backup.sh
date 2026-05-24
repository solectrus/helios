# shellcheck shell=bash
# Executed inside the docker:cli sidecar by BackupRunner. The container runs
# Alpine `ash` (not bash); `shell=bash` is the closest dialect Shellcheck
# supports that allows `set -o pipefail`.
# Receives positional args via `sh -c '<this script>' _ <token> <filename>
# <date> <postgres-container> <influxdb-container>`. Positional args are
# passed by argv (not interpolated) so values with shell metacharacters are
# safe. The InfluxDB inner pipeline matches what HELIOS ran before (`influx
# backup` + tar+gzip), just orchestrated from outside.
#
# This script no longer talks to the backup destination directly: it writes
# the final tar (or an error file) into /output (the staging dir) and exits.
# The HELIOS Rails process picks the artifact up afterwards and handles
# any remote upload via aws-sdk-s3.

set -eu
set -o pipefail

TOKEN="$1"
BACKUP_FILENAME="$2"
BACKUP_DATE="$3"
POSTGRES_CONTAINER="$4"
INFLUXDB_CONTAINER="$5"

OUTPUT_DIR="/output"
WORK_DIR="$OUTPUT_DIR/.work"
PG_FILE="$WORK_DIR/solectrus-postgresql-backup-$BACKUP_DATE.sql.gz"
INFLUX_FILE="$WORK_DIR/solectrus-influxdb-backup-$BACKUP_DATE.tar.gz"
CONFIG_DEST="$WORK_DIR/helios/config.yaml"
PART_PATH="$OUTPUT_DIR/$BACKUP_FILENAME.part"
FINAL_PATH="$OUTPUT_DIR/$BACKUP_FILENAME"
ERROR_PATH="$OUTPUT_DIR/error.txt"

fail() {
  echo "$1" > "$ERROR_PATH"
  rm -rf "$WORK_DIR"
  rm -f "$PART_PATH"
  exit 1
}

rm -rf "$WORK_DIR"
rm -f "$PART_PATH" "$ERROR_PATH"
mkdir -p "$WORK_DIR/helios"

# pg_dump's stderr is redirected to a log so the actual cause (e.g. "database
# does not exist") surfaces in error.txt instead of just the generic prefix.
PG_LOG="$WORK_DIR/postgresql-dump.log"
if ! docker exec "$POSTGRES_CONTAINER" \
       pg_dump -U postgres --clean --if-exists --dbname=solectrus_production \
     2> "$PG_LOG" \
     | gzip > "$PG_FILE"; then
  fail "PostgreSQL dump failed: $(tail -n 20 "$PG_LOG" | tr '\n' ' ')"
fi

[ -s "$PG_FILE" ] || fail "PostgreSQL dump produced empty output"

INFLUX_LOG="$WORK_DIR/influxdb-backup.log"
if ! docker exec "$INFLUXDB_CONTAINER" sh -c '
  set -e
  NAME="solectrus-influxdb-backup-$2"
  WORK="/tmp/$NAME"
  rm -rf "$WORK"
  trap "rm -rf $WORK" EXIT
  influx backup "$WORK" -t "$1" 1>&2
  tar -cz -C /tmp "$NAME"
' _ "$TOKEN" "$BACKUP_DATE" 2> "$INFLUX_LOG" > "$INFLUX_FILE"; then
  fail "InfluxDB backup failed: $(tail -n 20 "$INFLUX_LOG" | tr '\n' ' ')"
fi

[ -s "$INFLUX_FILE" ] || fail "InfluxDB backup produced empty output"

cp /config.yaml "$CONFIG_DEST" || fail "Failed to copy config.yaml"

# Outer tar is uncompressed: PG dump and Influx archive are already gzipped,
# so a second gzip layer wastes CPU on the (often Pi-class) host.
tar -cf "$PART_PATH" -C "$WORK_DIR" . || fail "Failed to bundle backup archive"

# No manifest sidecar is written here: file list, sizes and image versions
# are all read back from the archive itself. The `.json` sidecar only ever
# records a restore timestamp, and is written by restore.sh.
mv "$PART_PATH" "$FINAL_PATH"
rm -rf "$WORK_DIR"
