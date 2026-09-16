#!/bin/bash
# Nextcloud daily backup (Layer 1)
#
# Backs up, into a SECOND Scaleway S3 bucket (separate project, created by
# hand, outside Terraform):
#   1. a compressed dump of the Nextcloud PostgreSQL database
#   2. the Nextcloud config.php (contains passwordsalt/secret, mandatory to
#      restore encrypted files and user passwords)
#   3. a sync of all files from the primary S3 bucket
#
# Designed to run on the Nextcloud instance via a systemd timer. Independent
# of Terraform: the destination bucket and its IAM keys are NOT managed by
# Terraform, so `terraform destroy` cannot delete the backup.

set -euo pipefail

# ---------- config ----------
CONFIG_FILE="${NEXTCLOUD_BACKUP_CONFIG:-/etc/nextcloud-backup/nextcloud-backup.env}"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] config file not found: $CONFIG_FILE" >&2
    exit 2
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${BACKUP_RCLONE_SRC:?missing in config}"
: "${BACKUP_RCLONE_DST:?missing in config}"
: "${BACKUP_DB_HOST:?missing in config}"
: "${BACKUP_DB_PORT:?missing in config}"
: "${BACKUP_DB_NAME:?missing in config}"
: "${BACKUP_DB_USER:?missing in config}"
: "${BACKUP_DB_PASSWORD:?missing in config}"
: "${BACKUP_NEXTCLOUD_DIR:?missing in config}"
: "${BACKUP_RETENTION_DAYS:?missing in config}"

BACKUP_DATE="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_LOCAL_DIR:-/var/backups/nextcloud}"
DB_DUMP_FILE="$BACKUP_DIR/db-${BACKUP_DATE}.sql.gz"
DB_DUMP_LATEST="$BACKUP_DIR/db-latest.sql.gz"
CONFIG_ARCHIVE="$BACKUP_DIR/config-${BACKUP_DATE}.tar.gz"

LOG_TAG="nextcloud-backup"
log() { logger -t "$LOG_TAG" "$1"; echo "[$(date +%FT%T)] $1"; }

mkdir -p "$BACKUP_DIR"

# ---------- lock ----------
LOCK_FILE="/var/lock/nextcloud-backup.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "[WARN] another backup run is in progress, exiting"
    exit 0
fi

log "starting backup (date=$BACKUP_DATE)"

# ---------- 1. PostgreSQL dump ----------
log "dumping PostgreSQL database ${BACKUP_DB_NAME}@${BACKUP_DB_HOST}:${BACKUP_DB_PORT}"
PGPASSWORD="$BACKUP_DB_PASSWORD" pg_dump \
    --host="$BACKUP_DB_HOST" \
    --port="$BACKUP_DB_PORT" \
    --dbname="$BACKUP_DB_NAME" \
    --username="$BACKUP_DB_USER" \
    --format=custom \
    --no-owner --no-privileges \
    --file="$DB_DUMP_FILE.tmp"
gzip -c "$DB_DUMP_FILE.tmp" > "$DB_DUMP_FILE"
rm -f "$DB_DUMP_FILE.tmp"
cp -f "$DB_DUMP_FILE" "$DB_DUMP_LATEST"
log "db dump written: $DB_DUMP_FILE ($(du -h "$DB_DUMP_FILE" | cut -f1))"

# ---------- 2. config.php ----------
log "archiving Nextcloud config"
CONFIG_DIR="${BACKUP_NEXTCLOUD_DIR%/}/config"
tar -czf "$CONFIG_ARCHIVE.tmp" -C "$BACKUP_NEXTCLOUD_DIR" \
    config/config.php 2>/dev/null || \
    tar -czf "$CONFIG_ARCHIVE.tmp" -C "$CONFIG_DIR" .
mv "$CONFIG_ARCHIVE.tmp" "$CONFIG_ARCHIVE"
log "config archive written: $CONFIG_ARCHIVE"

# ---------- 3. sync files from primary S3 to backup S3 ----------
log "syncing files: ${BACKUP_RCLONE_SRC} -> ${BACKUP_RCLONE_DST}"
rclone sync "$BACKUP_RCLONE_SRC" "$BACKUP_RCLONE_DST" \
    --transfers 4 \
    --checkers 8 \
    --stats=0 \
    --log-file "/var/log/nextcloud-backup-rclone.log" \
    --log-level INFO
log "file sync done"

# ---------- 4. upload DB dump + config to backup bucket ----------
log "uploading db dump and config to backup bucket"
rclone copy "$DB_DUMP_FILE"    "${BACKUP_RCLONE_DST}/_nextcloud-db/"
rclone copy "$DB_DUMP_LATEST"  "${BACKUP_RCLONE_DST}/_nextcloud-db/"
rclone copy "$CONFIG_ARCHIVE"  "${BACKUP_RCLONE_DST}/_nextcloud-config/"

# ---------- 5. local retention ----------
log "applying local retention (${BACKUP_RETENTION_DAYS} days)"
find "$BACKUP_DIR" -maxdepth 1 -type f \( \
        -name 'db-*.sql.gz' -o \
        -name 'config-*.tar.gz' \) \
    -mtime "+${BACKUP_RETENTION_DAYS}" -delete
log "backup finished successfully"
