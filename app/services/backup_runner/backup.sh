# shellcheck shell=bash
# Executed inside the docker:cli sidecar by BackupRunner. The container runs
# Alpine `ash` (not bash); `shell=bash` is the closest dialect Shellcheck
# supports that allows `set -o pipefail`.
# Receives positional args via `sh -c '<this script>' _ <token> <filename>
# <date> <postgres-container> <influxdb-container>`. Positional args are
# passed by argv (not interpolated) so values with shell metacharacters
# are safe. The InfluxDB inner pipeline matches what HELIOS ran before
# (`influx backup` + tar+gzip), just orchestrated from outside.

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
MANIFEST_PATH="$FINAL_PATH.json"
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

docker exec "$POSTGRES_CONTAINER" \
  pg_dump -U postgres --clean --if-exists --dbname=solectrus_production \
  | gzip > "$PG_FILE" \
  || fail "PostgreSQL dump failed"

[ -s "$PG_FILE" ] || fail "PostgreSQL dump produced empty output"

docker exec "$INFLUXDB_CONTAINER" sh -c '
  set -e
  NAME="solectrus-influxdb-backup-$2"
  WORK="/tmp/$NAME"
  rm -rf "$WORK"
  trap "rm -rf $WORK" EXIT
  influx backup "$WORK" -t "$1" 1>&2
  tar -cz -C /tmp "$NAME"
' _ "$TOKEN" "$BACKUP_DATE" > "$INFLUX_FILE" \
  || fail "InfluxDB backup failed"

[ -s "$INFLUX_FILE" ] || fail "InfluxDB backup produced empty output"

cp /config.yaml "$CONFIG_DEST" || fail "Failed to copy config.yaml"

# Outer tar is uncompressed: PG dump and Influx archive are already gzipped,
# so a second gzip layer wastes CPU on the (often Pi-class) host.
tar -cf "$PART_PATH" -C "$WORK_DIR" . || fail "Failed to bundle backup archive"

PG_BYTES=$(wc -c < "$PG_FILE" | tr -d ' ')
INFLUX_BYTES=$(wc -c < "$INFLUX_FILE" | tr -d ' ')
CONFIG_BYTES=$(wc -c < /config.yaml | tr -d ' ')

cat > "$MANIFEST_PATH" <<JSON
{"entries":[{"name":"solectrus-postgresql-backup-$BACKUP_DATE.sql.gz","bytes":$PG_BYTES},{"name":"solectrus-influxdb-backup-$BACKUP_DATE.tar.gz","bytes":$INFLUX_BYTES},{"name":"helios/config.yaml","bytes":$CONFIG_BYTES}]}
JSON

mv "$PART_PATH" "$FINAL_PATH"
rm -rf "$WORK_DIR"
