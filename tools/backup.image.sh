#!/bin/bash

if [ $# -lt 3 ]; then
    echo "Usage: $0 <pattern> <remote_user> <remote_host> [remote_path]"
    echo "  pattern     : chaîne de caractères à rechercher dans les fichiers"
    echo "  remote_user : utilisateur SSH distant"
    echo "  remote_host : hôte distant"
    echo "  remote_path : chemin de destination sur la machine distante (par défaut: ~)"
    exit 1
fi

PATTERN="$1"
REMOTE_USER="$2"
REMOTE_HOST="$3"
REMOTE_PATH="${4:-~}" 

IMG_DIR="/var/lib/libvirt/images"

TAR_NAME="${PATTERN}.tar"
case "$PATTERN" in
    u2004)
        TAR_NAME="ubuntu20.tar"
        ;;
    u2204)
        TAR_NAME="ubuntu22.tar"
        ;;
    u2404)
        TAR_NAME="ubuntu24.tar"
        ;;
    u2604)
        TAR_NAME="ubuntu26.tar"
        ;;
esac

TAR_PATH="/tmp/$TAR_NAME"

cd "$IMG_DIR" || { echo "Impossible d'accéder à $IMG_DIR"; exit 1; }

echo "[*] Création de l’archive $TAR_PATH contenant les fichiers correspondant à '$PATTERN'..."
tar -cf "$TAR_PATH" *"$PATTERN"* 2>/dev/null

if [ $? -ne 0 ]; then
    echo "Erreur lors de la création de l'archive (aucun fichier correspondant ?)"
    exit 1
fi

echo "[*] Transfert de l’archive sur $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH..."
scp "$TAR_PATH" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/"
if [ $? -ne 0 ]; then
    echo "Erreur lors du transfert SCP"
    exit 1
fi

CHECKSUM=$(sha256sum "$TAR_PATH" | awk '{print $1}')
echo "[*] SHA256 local : $CHECKSUM"

CHECKSUM_FILE="${TAR_NAME}.sha256"
echo "$CHECKSUM  $TAR_NAME" > "/tmp/$CHECKSUM_FILE"

scp "/tmp/$CHECKSUM_FILE" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/"
if [ $? -ne 0 ]; then
    echo "Erreur lors du transfert du checksum"
    exit 1
fi

echo "[*] Terminé ! Archive et checksum transférés sur $REMOTE_HOST:$REMOTE_PATH"
