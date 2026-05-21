# shellcheck shell=bash
# Executed inside the docker:cli sidecar by BackupRunner. The container runs
# Alpine `ash` (not bash); `shell=bash` is the closest dialect Shellcheck
# supports that allows `set -o pipefail`.
# Receives positional args via `sh -c '<this script>' _ <token> <filename>
# <date> <postgres-container> <influxdb-container> <destination>
# <host-staging> <aws-cli-image> <s3-dir-uri>`. Positional args are passed
# by argv (not interpolated) so values with shell metacharacters are safe.
# The InfluxDB inner pipeline matches what HELIOS ran before (`influx
# backup` + tar+gzip), just orchestrated from outside.

set -eu
set -o pipefail

TOKEN="$1"
BACKUP_FILENAME="$2"
BACKUP_DATE="$3"
POSTGRES_CONTAINER="$4"
INFLUXDB_CONTAINER="$5"
DESTINATION="$6"
HOST_STAGING="$7"
AWS_CLI_IMAGE="$8"
S3_DIR_URI="$9"

OUTPUT_DIR="/output"
WORK_DIR="$OUTPUT_DIR/.work"
PG_FILE="$WORK_DIR/solectrus-postgresql-backup-$BACKUP_DATE.sql.gz"
INFLUX_FILE="$WORK_DIR/solectrus-influxdb-backup-$BACKUP_DATE.tar.gz"
CONFIG_DEST="$WORK_DIR/helios/config.yaml"
PART_PATH="$OUTPUT_DIR/$BACKUP_FILENAME.part"
FINAL_PATH="$OUTPUT_DIR/$BACKUP_FILENAME"
ERROR_PATH="$OUTPUT_DIR/error.txt"

# Bind-mount + env forwarding for the nested aws-cli sidecar. AWS_ENDPOINT_URL
# is omitted from the inherited env list when blank so the inner CLI falls
# back to its default (AWS S3); $inner_env is intentionally word-split.
inner_env="-e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION"
if [ -n "${AWS_ENDPOINT_URL:-}" ]; then
  inner_env="$inner_env -e AWS_ENDPOINT_URL"
fi

s3_upload() {
  src_basename="$(basename "$1")"
  # shellcheck disable=SC2086
  docker run --rm -v "$HOST_STAGING:/work" $inner_env "$AWS_CLI_IMAGE" \
    s3 cp "/work/$src_basename" "$2"
}

fail() {
  echo "$1" > "$ERROR_PATH"
  rm -rf "$WORK_DIR"
  rm -f "$PART_PATH"
  if [ "$DESTINATION" = "s3" ]; then
    # Drop the local copy only once it is safely on S3 — otherwise an
    # unreachable destination would erase the failure without a trace.
    if s3_upload "$ERROR_PATH" "${S3_DIR_URI}error.txt" 2>/dev/null; then
      rm -f "$ERROR_PATH"
    fi
  fi
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

# No manifest sidecar is written here: file list, sizes and image versions
# are all read back from the archive itself. The `.json` sidecar only ever
# records a restore timestamp, and is written by restore.sh.
mv "$PART_PATH" "$FINAL_PATH"
rm -rf "$WORK_DIR"

# For S3 destinations the local tar is staging only: upload it through a
# nested aws-cli container (the outer docker:cli image carries no AWS CLI)
# and remove the local copy. The staging directory then holds at most one
# in-flight backup, never a full archive listing.
if [ "$DESTINATION" = "s3" ]; then
  s3_upload "$FINAL_PATH" "${S3_DIR_URI}${BACKUP_FILENAME}" || fail "S3 upload failed"
  rm -f "$FINAL_PATH"
fi
