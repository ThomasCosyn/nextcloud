#!/usr/bin/env bash
# Migration Google Drive -> Nextcloud avec classement annee/mois par metadata EXIF
#
# Prerequis :
#   - Google Takeout telecharge et dezippe (ou tout dossier de photos)
#   - exiftool installe : sudo apt-get install libimage-exiftool-perl
#   - rclone configure avec un remote WebDAV vers votre Nextcloud :
#       rclone config
#         n) new remote -> nom: nextcloud
#         type: webdav
#         url: https://nextcloud.goossaertcosyn.fr/remote.php/dav
#         vendor: nextcloud
#         user: <votre utilisateur>
#         pass: <rclone demande, il chiffre>
#
# Usage :
#   ./gdrive_photos_to_nextcloud.sh <dossier_source> <dossier_nextcloud_cible>
# Exemple :
#   ./gdrive_photos_to_nextcloud.sh ~/Takeout/Google\ Photos /Photos

set -euo pipefail

SRC="${1:?Usage: $0 <dossier_source> <dossier_nextcloud_cible>}"
DEST="${2:?Usage: $0 <dossier_source> <dossier_nextcloud_cible>}"
REMOTE="nextcloud"                     # nom du remote rclone
DRY_RUN="${DRY_RUN:-1}"                # 1 = classement seulement (test), 0 = upload
DEFAULT_DATE_DIR="0000/00"             # quand aucune date EXIF n'est trouvee

command -v exiftool >/dev/null || { echo "exiftool manquant: apt-get install libimage-exiftool-perl"; exit 1; }
command -v rclone  >/dev/null || { echo "rclone manquant: https://rclone.org/install/"; exit 1; }
rclone listremotes 2>/dev/null | grep -q "^${REMOTE}:" || { echo "remote rclone '${REMOTE}' inconnu (rclone config)"; exit 1; }

echo "Source: $SRC"
echo "Destination Nextcloud: $DEST"
[ "$DRY_RUN" = "1" ] && echo "DRY_RUN=1 (classement local seulement, pas d'upload)"

# Extensions prises en compte
shopt -s nullglob nocaseglob
FILES=()
for ext in jpg jpeg png heic heif mp4 mov avi webp; do
    FILES+=("$SRC"/**/*.$ext "$SRC"/*.$ext)
done
shopt -u nocaseglob

echo "${#FILES[@]} fichiers trouves"

STAGING="$(mktemp -d)/upload"
trap 'rm -rf "$(dirname "$STAGING")"' EXIT
mkdir -p "$STAGING"

for f in "${FILES[@]}"; do
    # Date EXIF : DateTimeOriginal, sinon CreateDate, sinon date du fichier
    date=$(exiftool -s3 -d "%Y/%m" -DateTimeOriginal -CreateDate -filemodifydate "$f" 2>/dev/null | head -1)
    [ -z "$date" ] && date="$DEFAULT_DATE_DIR"

    dest_rel="$date/$(basename "$f")"
    dest_local="$STAGING/$dest_rel"
    mkdir -p "$(dirname "$dest_local")"
    cp -- "$f" "$dest_local"
done

echo "Classement local termine dans: $STAGING"
echo "Apercu:"
find "$STAGING" -type f | sed "s#$STAGING/##" | sort | head -20

if [ "$DRY_RUN" = "1" ]; then
    echo ""
    echo "DRY_RUN actif : rien n'a ete uploade."
    echo "Relancez avec DRY_RUN=0 $0 $SRC $DEST pour envoyer vers Nextcloud."
    exit 0
fi

echo "Upload vers Nextcloud ($REMOTE:$DEST) ..."
rclone copy "$STAGING" "${REMOTE}:${DEST}" \
    --transfers 4 --checkers 8 \
    --log-file "$(dirname "$0")/upload.log" --log-level INFO

echo "Termine. Fichiers envoyes dans $DEST, structure annee/mois."
echo "Verifiez : $REMOTE ls ${REMOTE}:${DEST}"
