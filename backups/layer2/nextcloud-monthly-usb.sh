#!/bin/bash
# Nextcloud monthly backup to an external medium (Layer 2)
#
# Copies onto a mounted external medium (USB key / hard drive):
#   1. a compressed dump of the Nextcloud PostgreSQL database
#   2. the Nextcloud config.php
#   3. ALL files from the Layer 1 backup bucket (so this works even if the
#      Nextcloud instance itself is down)
#
# Everything is written client-side encrypted via rclone crypt, so the medium
# is useless without the rclone crypt password. The medium never holds
# plaintext.
#
# This is a MANUAL, on-demand script: run it when you do your monthly backup.
# Prerequisite: rclone configured with the Layer 1 backup remote
# (scaleway-backup) AND a `usb-crypt` crypt remote. See layer2/README.md.

set -euo pipefail

# ---------- config ----------
CONFIG_FILE="${NEXTCLOUD_BACKUP_CONFIG:-/etc/nextcloud-backup/nextcloud-backup.env}"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] config file not found: $CONFIG_FILE" >&2
    echo "        (this script reuses the Layer 1 config for DB credentials)" >&2
    exit 2
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${BACKUP_DB_HOST:?missing in config}"
: "${BACKUP_DB_PORT:?missing in config}"
: "${BACKUP_DB_NAME:?missing in config}"
: "${BACKUP_DB_USER:?missing in config}"
: "${BACKUP_DB_PASSWORD:?missing in config}"
: "${BACKUP_NEXTCLOUD_DIR:?missing in config}"

# The Layer 1 backup bucket remote (encrypted source of truth for files).
LAYER1_REMOTE="${LAYER1_REMOTE:-scaleway-backup:nextcloud-backup}"
# The crypt remote mounted at the USB key mount point.
USB_CRYPT_REMOTE="${USB_CRYPT_REMOTE:-usb-crypt:}"

BACKUP_DATE="$(date +%Y%m%d-%H%M%S)"
LOCAL_WORK_DIR="${LOCAL_WORK_DIR:-/var/backups/nextcloud-monthly}"

log() { echo "[$(date +%FT%T)] $1"; }

mkdir -p "$LOCAL_WORK_DIR"

# ---------- 1. PostgreSQL dump ----------
log "dumping PostgreSQL database ${BACKUP_DB_NAME}@${BACKUP_DB_HOST}:${BACKUP_DB_PORT}"
DB_DUMP_FILE="$LOCAL_WORK_DIR/db-${BACKUP_DATE}.sql.gz"
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
log "db dump written: $DB_DUMP_FILE ($(du -h "$DB_DUMP_FILE" | cut -f1))"

# ---------- 2. config.php ----------
log "archiving Nextcloud config"
CONFIG_ARCHIVE="$LOCAL_WORK_DIR/config-${BACKUP_DATE}.tar.gz"
CONFIG_DIR="${BACKUP_NEXTCLOUD_DIR%/}/config"
tar -czf "$CONFIG_ARCHIVE.tmp" -C "$BACKUP_NEXTCLOUD_DIR" \
    config/config.php 2>/dev/null || \
    tar -czf "$CONFIG_ARCHIVE.tmp" -C "$CONFIG_DIR" .
mv "$CONFIG_ARCHIVE.tmp" "$CONFIG_ARCHIVE"

# ---------- 3. copy everything to the encrypted USB medium ----------
log "copying db dump + config to ${USB_CRYPT_REMOTE}_nextcloud/"
rclone copy "$DB_DUMP_FILE"    "${USB_CRYPT_REMOTE}_nextcloud/db/"
rclone copy "$CONFIG_ARCHIVE"  "${USB_CRYPT_REMOTE}_nextcloud/config/"

log "syncing all files from Layer 1 bucket -> ${USB_CRYPT_REMOTE}_nextcloud/files/"
rclone sync "$LAYER1_REMOTE" "${USB_CRYPT_REMOTE}_nextcloud/files/" \
    --transfers 4 \
    --checkers 8 \
    --stats=1m 0s \
    --log-level INFO

# ---------- 4. retention on the USB medium (optional) ----------
# Keep only the last N monthly DB/config snapshots on the key; files are
# mirrored (sync) so they are always up to date.
KEEP_MONTHS="${KEEP_MONTHS:-3}"
log "pruning USB medium to last ${KEEP_MONTHS} monthly db/config snapshots"
rclone delete "${USB_CRYPT_REMOTE}_nextcloud/db/" \
    --min-age "${KEEP_MONTHS}months" 2>/dev/null || true
rclone delete "${USB_CRYPT_REMOTE}_nextcloud/config/" \
    --min-age "${KEEP_MONTHS}months" 2>/dev/null || true

# clean local working dir
find "$LOCAL_WORK_DIR" -maxdepth 1 -type f -mtime +1 -delete 2>/dev/null || true

log "monthly backup finished successfully"
log "verify with: rclone lsd ${USB_CRYPT_REMOTE}_nextcloud/"
log "safe-eject the medium before unplugging it."
