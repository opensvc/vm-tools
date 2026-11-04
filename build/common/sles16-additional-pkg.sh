#!/bin/bash

echo "custom packages installation"

zypper --non-interactive --gpg-auto-import-keys install os-autoinst-qemu-kvm virt-install virt-manager guestfs-tools bridge-utils git jq mkisofs lxc lxc-bash-completion debootstrap

exit 0
