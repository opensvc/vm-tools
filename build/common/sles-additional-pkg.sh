#!/bin/bash

echo "custom packages installation"

zypper --non-interactive --gpg-auto-import-keys install qemu-kvm virt-install virt-manager guestfs-tools bridge-utils git curl jq dnsmasq

# only available on sles15
grep -q 'suse:sles:15' /etc/os-release && {
    zypper --non-interactive --gpg-auto-import-keys install mkisofs cni cni-plugins lxc lxc-bash-completion debootstrap
}

exit 0
