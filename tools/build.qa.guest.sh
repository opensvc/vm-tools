#!/bin/bash

# Build the guest image the qatests kvm tests run in the lab nodes: the
# official alpine nocloud image, with the qemu guest agent enabled at boot, so
# the tests run commands in the guest with virsh qemu-agent-command, with no
# network to the guest.
#
# The image is checked against the sha512 alpine publishes, and written as
# <dest>/alpine-qga-<version>.qcow2, replaced by a rename.
#
# usage: build.qa.guest.sh [dest dir]
#   dest dir: /data/nfsshare/kvm by default, the share the lab nodes mount
#             on /nfs/data

set -o pipefail

ALPINE_BRANCH=${ALPINE_BRANCH:-v3.20}
ALPINE_VERSION=${ALPINE_VERSION:-3.20.9}
DEST=${1:-/data/nfsshare/kvm}

SRC=nocloud_alpine-${ALPINE_VERSION}-x86_64-bios-tiny-r0.qcow2
URL=https://dl-cdn.alpinelinux.org/alpine/$ALPINE_BRANCH/releases/cloud/$SRC
IMAGE=alpine-qga-${ALPINE_VERSION}.qcow2

WORK=$(mktemp -d) || exit 1
trap 'rm -rf $WORK' EXIT
cd $WORK || exit 1

echo "Download $URL"
curl -fsSLO $URL && curl -fsSL $URL.sha512 -o $SRC.sha512 || {
    echo "unable to download $URL"
    exit 1
}
[ "$(cut -d' ' -f1 $SRC.sha512)" = "$(sha512sum $SRC | cut -d' ' -f1)" ] || {
    echo "$SRC does not match its sha512"
    exit 1
}

echo "Add the qemu guest agent"
LIBGUESTFS_BACKEND=direct virt-customize -a $SRC --network \
    --run-command 'apk add --no-cache qemu-guest-agent' \
    --run-command 'rc-update add qemu-guest-agent default' || {
    echo "unable to customize $SRC"
    exit 1
}
LIBGUESTFS_BACKEND=direct virt-cat -a $SRC /etc/runlevels/default/qemu-guest-agent >/dev/null || {
    echo "qemu-guest-agent is not enabled in $SRC"
    exit 1
}

mkdir -p $DEST && \
    cp $SRC $DEST/.$IMAGE.tmp && \
    mv -f $DEST/.$IMAGE.tmp $DEST/$IMAGE || {
    rm -f $DEST/.$IMAGE.tmp
    echo "unable to install $DEST/$IMAGE"
    exit 1
}
echo "Built $DEST/$IMAGE"
