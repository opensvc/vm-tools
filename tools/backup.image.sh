#!/bin/bash

set -o pipefail

if [ $# -lt 3 ]; then
    echo "Usage: $0 <image> <remote_user> <remote_host> [remote_path]"
    echo "  image       : nom de l'image (rhel9, u2404, debian13, sles12sp5, sles15sp7, ...)"
    echo "  remote_user : utilisateur SSH distant"
    echo "  remote_host : hôte distant"
    echo "  remote_path : chemin de destination sur la machine distante (par défaut: ~)"
    echo
    echo "  REMOTE_SUDO=sudo $0 ... : écrit sur la machine distante via sudo"
    exit 1
fi

IMAGE="$1"
REMOTE_USER="$2"
REMOTE_HOST="$3"
REMOTE_PATH="${4:-~}"
REMOTE_SUDO="${REMOTE_SUDO:-}"

IMG_DIR="${IMG_DIR:-/var/lib/libvirt/images}"

TAR_NAME="${IMAGE}.tar"
EFIVARS="${IMAGE}.efivars.fd"
case "$IMAGE" in
    u2004|u2204|u2404|u2604)
        TAR_NAME="ubuntu${IMAGE:1:2}.tar"
        ;;
    sles12sp5)
        TAR_NAME="sles12.tar"
        EFIVARS="sles12.efivars.fd"
        ;;
    sles15sp*)
        EFIVARS="sles15.efivars.fd"
        ;;
esac

cd "$IMG_DIR" || { echo "Impossible d'accéder à $IMG_DIR"; exit 1; }

# only the image and its uefi vars, never backups or stray archives
FILES=("packer-uefi-${IMAGE}.qcow2")
[[ -f "${FILES[0]}" ]] || { echo "Image $IMG_DIR/${FILES[0]} introuvable"; exit 1; }
[[ -f "$EFIVARS" ]] && FILES+=("$EFIVARS")

DEST="$REMOTE_USER@$REMOTE_HOST"
SSH="ssh -o BatchMode=yes"

# the new archive is written next to the old one before replacing it
SIZE_KB=$(du -kc "${FILES[@]}" | tail -1 | cut -f1)
AVAIL_KB=$($SSH "$DEST" "df -Pk $REMOTE_PATH | tail -1" | awk '{print $4}')
[[ -n "$AVAIL_KB" ]] || { echo "Impossible de lire l'espace libre de $DEST:$REMOTE_PATH"; exit 1; }
if (( AVAIL_KB < SIZE_KB + 1048576 )); then
    echo "Espace insuffisant sur $DEST:$REMOTE_PATH (${AVAIL_KB} KB libres, ${SIZE_KB} KB requis + 1 GB)"
    exit 1
fi

LOCAL_SUM_FILE=$(mktemp)
REMOTE_SUM_FILE=$(mktemp)
trap 'rm -f "$LOCAL_SUM_FILE" "$REMOTE_SUM_FILE"' EXIT

echo "[*] Envoi de ${FILES[*]} vers $DEST:$REMOTE_PATH/$TAR_NAME..."
tar -cf - "${FILES[@]}" \
    | tee >(sha256sum > "$LOCAL_SUM_FILE") \
    | $SSH "$DEST" "cd $REMOTE_PATH && $REMOTE_SUDO tee .$TAR_NAME.part > /dev/null && $REMOTE_SUDO sha256sum .$TAR_NAME.part" \
    > "$REMOTE_SUM_FILE"
RC=$?
wait $!

LOCAL_SUM=$(awk '{print $1}' "$LOCAL_SUM_FILE")
REMOTE_SUM=$(awk '{print $1}' "$REMOTE_SUM_FILE")
if [[ $RC -ne 0 || -z "$LOCAL_SUM" || "$LOCAL_SUM" != "$REMOTE_SUM" ]]; then
    echo "Erreur lors du transfert (rc=$RC, local=$LOCAL_SUM, distant=$REMOTE_SUM)"
    $SSH "$DEST" "cd $REMOTE_PATH && $REMOTE_SUDO rm -f .$TAR_NAME.part"
    exit 1
fi
echo "[*] SHA256 vérifié des deux côtés : $LOCAL_SUM"

$SSH "$DEST" "cd $REMOTE_PATH && $REMOTE_SUDO mv -f .$TAR_NAME.part $TAR_NAME && echo '$LOCAL_SUM  $TAR_NAME' | $REMOTE_SUDO tee $TAR_NAME.sha256 > /dev/null" || {
    echo "Erreur lors de la mise en place de $TAR_NAME"
    exit 1
}

echo "[*] Terminé ! $TAR_NAME et $TAR_NAME.sha256 mis à jour sur $REMOTE_HOST:$REMOTE_PATH"
