#!/bin/bash -eu

echo "--- Begin zfs.sh ---"

export DEBIAN_FRONTEND=noninteractive

apt -y update && apt -y install zfsutils-linux

echo "--- End zfs.sh ---"
