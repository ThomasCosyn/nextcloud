#!/usr/bin/env bash
# Migration Google Drive -> Nextcloud via rclone, avec tri annee/mois par EXIF
#
# Contrairement a gdrive_photos_to_nextcloud.sh (qui part d'un Takeout local),
# ce script lit DIRECTEMENT dans Google Drive via rclone (OAuth compte perso,
# pas de compte de service necessaire).
#
# Recommande: a lancer SUR l'instance Nextcloud (bande passante datacenter),
# mais fonctionne aussi depuis votre ordinateur.
#
# Prerequis :
#   sudo apt-get install libimage-exiftool-perl
#   rclone installe : https://rclone.org/install/
#
#   Deux remotes rclone a configurer (rclone config) :
#     - "gdrive"    : type drive, auth OAuth avec VOTRE compte Google
#         (repondre non a service_account_file, une URL s'ouvre, vous autorisez)
#     - "nextcloud" : type webdav, vendor nextcloud,
#         url https://nextcloud.goossaertcosyn.fr/remote.php/dav, votre user
#
# Usage :
#   ./gdrive_rclone_to_nextcloud.sh <chemin_gdrive> <dossier_nextcloud_cible>
# Exemples :
#   ./gdrive_rclone_to_nextcloud.sh "gdrive:Photos" /Photos
#   ./gdrive_rclone_to_nextcloud.sh "gdrive:" /Photos        # tout le drive
#
# Variables d'environnement :
#   DRY_RUN=0  desactive le mode test (par defaut 1 = download+tri mais pas d'upload)
#   STAGING_DIR=/var/tmp/gdrive_migration  pour choisir ou poser les fichiers temporaires

set -euo pipefail

GDRIVE_SRC="${1:?Usage: $0 <chemin_gdrive> <dossier_nextcloud_cible>}"
DEST="${2:?Usage: $0 <chemin_gdrive> <dossier_nextcloud_cible>}"
GDRIVE_REMOTE="gdrive"
NC_REMOTE="nextcloud"
DRY_RUN="${DRY_RUN:-1}"
STAGING="${STAGING_DIR:-/var/tmp/gdrive_migration}"
LOG_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_DATE_DIR="0000/00"     # fichiers sans date EXIF ni date fichier

command -v exiftool >/dev/null || { echo "exiftool manquant: apt-get install libimage-exiftool-perl"; exit 1; }
command -v rclone  >/dev/null || { echo "rclone manquant: https://rclone.org/install/"; exit 1; }

for r in "$GDRIVE_REMOTE" "$NC_REMOTE"; do
    rclone listremotes 2>/dev/null | grep -q "^${r}:" || { echo "remote rclone '${r}' inconnu (rclone config)"; exit 1; }
done

case "$GDRIVE_SRC" in
    "${GDRIVE_REMOTE}:"*) ;;
    *) echo "Le chemin source doit commencer par ${GDRIVE_REMOTE}: (ex: ${GDRIVE_REMOTE}:Photos)"; exit 1;;
esac

echo "Source Google Drive : $GDRIVE_SRC"
echo "Destination        : ${NC_REMOTE}:${DEST}"
echo "Staging            : $STAGING"
[ "$DRY_RUN" = "1" ] && echo "DRY_RUN=1 : download + tri, PAS d'upload (test)"

echo ""
echo "=== 1/4 Listing du contenu Google Drive ==="
rclone lsf -R --files-only "$GDRIVE_SRC" | tee "${LOG_DIR}/gdrive_listing.txt" | wc -l | xargs -I{} echo "{} fichiers listes"

echo ""
echo "=== 2/4 Telechargement depuis Google Drive ==="
mkdir -p "$STAGING/download"
rclone copy "$GDRIVE_SRC" "$STAGING/download" \
    --transfers 4 --checkers 8 \
    --log-file "${LOG_DIR}/gdrive_download.log" --log-level INFO
echo "Telechargement termine."

echo ""
echo "=== 3/4 Tri par date EXIF (annee/mois) ==="
SORTED="$STAGING/sorted"
rm -rf "$SORTED"
mkdir -p "$SORTED"

shopt -s nullglob nocaseglob
count=0
no_date=0
while IFS= read -r -d '' f; do
    date=$(exiftool -s3 -d "%Y/%m" -DateTimeOriginal -CreateDate -filemodifydate "$f" 2>/dev/null | head -1)
    if [ -z "$date" ]; then
        date="$DEFAULT_DATE_DIR"
        no_date=$((no_date + 1))
    fi
    dest_dir="$SORTED/$date"
    mkdir -p "$dest_dir"
    # suffixe anti-collision si deux photos de dossiers differents portent le meme nom
    base=$(basename "$f")
    if [ -e "$dest_dir/$base" ]; then
        base="${base%.*}_$(date +%s%N).${base##*.}"
    fi
    cp -- "$f" "$dest_dir/$base"
    count=$((count + 1))
done < <(find "$STAGING/download" -type f -print0)
shopt -u nocaseglob

echo "$count fichiers classes"
[ "$no_date" -gt 0 ] && echo "ATTENTION: $no_date fichiers sans date EXIF -> $DEFAULT_DATE_DIR (a trier manuellement)"

echo ""
echo "Apercu du classement (20 premiers) :"
find "$SORTED" -type f | sed "s#$SORTED/##" | sort | head -20

if [ "$DRY_RUN" = "1" ]; then
    echo ""
    echo "DRY_RUN actif : rien n'a ete uploade."
    echo "Verifier $SORTED puis relancer avec :"
    echo "  DRY_RUN=0 $0 $GDRIVE_SRC $DEST"
    exit 0
fi

echo ""
echo "=== 4/4 Upload vers Nextcloud ==="
rclone copy "$SORTED" "${NC_REMOTE}:${DEST}" \
    --transfers 4 --checkers 8 \
    --log-file "${LOG_DIR}/nc_upload.log" --log-level INFO

echo ""
echo "Termine : $count fichiers envoyes dans ${NC_REMOTE}:${DEST} (structure annee/mois)"
echo "Logs: ${LOG_DIR}/gdrive_download.log et ${LOG_DIR}/nc_upload.log"

# Nettoyage optionnel (decommenter une fois la migration validee dans l'interface) :
# rm -rf "$STAGING"
