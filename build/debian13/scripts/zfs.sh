#!/bin/bash -eu

echo "--- Begin zfs.sh ---"

export DEBIAN_FRONTEND=noninteractive

apt -y update && apt -y install linux-headers-amd64 zfsutils-linux zfs-dkms zfs-zed

apt-mark hold zfsutils-linux zfs-zed zfs-dkms

echo "--- End zfs.sh ---"
