#!/bin/bash

# Remove the pinned base images (see pin_base_image in kvm.provision.sh) that
# no vm uses anymore: the published image has been replaced (link count 1)
# and no defined domain has the pinned image in the backing chain of a disk.
#
# usage: image.gc.sh [-n]
#   -n: dry run, only show what would be removed

KVM_IMAGES_ROOT=${KVM_IMAGES_ROOT:-/var/lib/libvirt/images}
PINNED_DIR=$KVM_IMAGES_ROOT/pinned

DRY_RUN=false
if [ "$1" = "-n" ]; then
    DRY_RUN=true
fi

if [ ! -d $PINNED_DIR ]; then
    exit 0
fi

# kvm.provision.sh holds this lock from pinning until its domain is defined
exec 9>$PINNED_DIR/.lock
flock -w 600 9 || { echo "unable to lock $PINNED_DIR"; exit 1; }

USED=$(mktemp)
trap 'rm -f $USED' EXIT

# every file of every disk backing chain, for all the defined domains
for DOMAIN in $(virsh list --all --name); do
    for DISK in $(virsh domblklist $DOMAIN --details | awk '$1=="file" && $2=="disk" {print $4}'); do
        CHAIN=$(qemu-img info -U --backing-chain --output=json $DISK) || {
            echo "unable to read the backing chain of $DISK, nothing removed"
            exit 1
        }
        echo "$CHAIN" | jq -r '.[].filename' | xargs -r realpath -m >> $USED
    done
done

for PINNED in $PINNED_DIR/*.qcow2; do
    if [ ! -f "$PINNED" ]; then
        continue
    fi
    if [ $(stat -c %h $PINNED) -gt 1 ]; then
        # still the published base image
        continue
    fi
    if grep -qxF "$(realpath $PINNED)" $USED; then
        continue
    fi
    if [ $DRY_RUN = true ]; then
        echo "would remove unused $PINNED"
    else
        echo "removing unused $PINNED"
        rm -f $PINNED
    fi
done
