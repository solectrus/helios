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
RUNTIME_DIR="/runtime"
# Intermediate dumps + config copy stay in /runtime (HELIOS-local), never on
# /output. Two reasons: (1) on a remote destination (NAS/SMB/S3 staging)
# writing multi-GB dumps there is wasteful — the final tar is the only
# artifact that has to land at the destination; (2) macOS SMB creates
# `.smbdelete*` tombstones when files are unlinked in-place, which causes
# `rmdir` on the work dir to fail with "Directory not empty" on the next
# run. Keeping work local sidesteps both.
WORK_DIR="$RUNTIME_DIR/work"
PG_FILE="$WORK_DIR/solectrus-postgresql-backup-$BACKUP_DATE.sql.gz"
CONFIG_DEST="$WORK_DIR/helios/config.yaml"
# Shared bind mount: InfluxDB writes its backup directly here, and we
# tar-stream it straight into the final archive without a docker-exec
# pipe or a second gzip pass. The same path exists in both containers.
INFLUX_STAGING="/influx-backup-staging"
INFLUX_NAME="solectrus-influxdb-backup-$BACKUP_DATE"
INFLUX_DIR="$INFLUX_STAGING/$INFLUX_NAME"
PART_PATH="$OUTPUT_DIR/$BACKUP_FILENAME.part"
FINAL_PATH="$OUTPUT_DIR/$BACKUP_FILENAME"
# Error + phase markers share the local /runtime dir, never /output. If the
# destination itself is the problem (full disk, read-only NFS, vanished
# mount, root_squash permission-denied), writing the failure note to
# /output would fail too — HELIOS would then only see the generic
# "process stopped" fallback. /runtime is HELIOS-local and always writable.
ERROR_PATH="$RUNTIME_DIR/error.txt"
PHASE_PATH="$RUNTIME_DIR/backup-phase.txt"
# Diagnostic logs for the inner dump commands. Kept in /runtime so a successful
# run never tars them into the final archive; the previous run's logs are
# wiped on startup below so stale output doesn't mislead future debugging.
PG_LOG="$RUNTIME_DIR/postgresql-dump.log"
INFLUX_LOG="$RUNTIME_DIR/influxdb-backup.log"

# Atomic write so BackupRunner.current_phase never reads a half-written name.
set_phase() {
  printf '%s\n' "$1" > "$PHASE_PATH.tmp" && mv "$PHASE_PATH.tmp" "$PHASE_PATH"
}

fail() {
  echo "$1" > "$ERROR_PATH"
  rm -f "$PHASE_PATH"
  rm -rf "$WORK_DIR"
  rm -rf "$INFLUX_DIR"
  rm -f "$PART_PATH"
  exit 1
}

rm -rf "$WORK_DIR" || fail "Failed to clean work directory: $WORK_DIR"
rm -f "$PART_PATH" "$ERROR_PATH" "$PHASE_PATH" "$PG_LOG" "$INFLUX_LOG"
mkdir -p "$WORK_DIR/helios"

set_phase dumping_postgres
# pg_dump's stderr is redirected to a log so the actual cause (e.g. "database
# does not exist") surfaces in error.txt instead of just the generic prefix.
if ! docker exec "$POSTGRES_CONTAINER" \
       pg_dump -U postgres --clean --if-exists --dbname=solectrus_production \
     2> "$PG_LOG" \
     | gzip > "$PG_FILE"; then
  fail "PostgreSQL dump failed: $(tail -n 20 "$PG_LOG" | tr '\n' ' ')"
fi

[ -s "$PG_FILE" ] || fail "PostgreSQL dump produced empty output"

set_phase dumping_influx
# Clear any leftover staging from an interrupted previous run, then let
# `influx backup` write straight into the shared mount. No stdio pipe,
# no /tmp page-cache pressure inside the InfluxDB container.
rm -rf "$INFLUX_DIR" || fail "Failed to clean InfluxDB staging dir: $INFLUX_DIR"
if ! docker exec "$INFLUXDB_CONTAINER" \
       influx backup "$INFLUX_DIR" -t "$TOKEN" \
     2> "$INFLUX_LOG"; then
  fail "InfluxDB backup failed: $(tail -n 20 "$INFLUX_LOG" | tr '\n' ' ')"
fi

if [ ! -d "$INFLUX_DIR" ] || [ -z "$(ls -A "$INFLUX_DIR" 2>/dev/null)" ]; then
  fail "InfluxDB backup produced no output"
fi

set_phase bundling
cp /config.yaml "$CONFIG_DEST" || fail "Failed to copy config.yaml"

# The InfluxDB backup lives on a different bind-mount (staging) than the
# rest of the work dir (runtime), and BusyBox tar applies only the last
# `-C` globally and lacks `-r` (append) and `--transform`. Symlink the
# staging dir into the work dir and let `tar -h` dereference it — the
# files land under solectrus-influxdb-backup-DATE/ in the archive
# without ever copying multi-GB out of the staging mount.
ln -s "$INFLUX_DIR" "$WORK_DIR/$INFLUX_NAME" \
  || fail "Failed to link InfluxDB backup into work directory"

# Outer tar is uncompressed: PG dump is already gzipped, and `influx
# backup` ships its own *.tar.gz / *.bolt.gz / *.sqlite.gz — a second
# gzip layer would just burn CPU on a (often Pi-class) host.
tar -cf "$PART_PATH" -C "$WORK_DIR" -h . \
  || fail "Failed to bundle backup archive"

mv "$PART_PATH" "$FINAL_PATH" || fail "Failed to publish backup archive: $FINAL_PATH"
rm -f "$PHASE_PATH"
rm -rf "$WORK_DIR" || fail "Failed to clean work directory after backup: $WORK_DIR"
rm -rf "$INFLUX_DIR" || fail "Failed to clean InfluxDB staging dir after backup: $INFLUX_DIR"
