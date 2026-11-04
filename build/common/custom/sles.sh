#!/bin/bash

zypper --non-interactive --gpg-auto-import-keys install htop lsscsi socat


# serial console config
cp /etc/default/grub /etc/default/grub.osvcpacker
sed -i 's/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=3/' /etc/default/grub
sed -i 's/SUSE_BTRFS_SNAPSHOT_BOOTING="true"/SUSE_BTRFS_SNAPSHOT_BOOTING="false"/' /etc/default/grub
sed -i 's#^\(GRUB_CMDLINE_LINUX_DEFAULT=.*\)"$#\1 console=tty0 console=ttyS0,115200n8"#' /etc/default/grub
sed -i 's#^GRUB_TERMINAL=.*$#GRUB_TERMINAL="console serial"#' /etc/default/grub
grep -q '^GRUB_TERMINAL=' /etc/default/grub || echo 'GRUB_TERMINAL="console serial"' >> /etc/default/grub

grub2-mkconfig -o /boot/grub2/grub.cfg
grub2-mkconfig -o /boot/efi/EFI/sles/grub.cfg

systemctl -q is-enabled firewalld.service && {
    echo "Disable firewalld service"
    systemctl disable firewalld.service
}

systemctl -q is-enabled docker.service || {
    echo "Enable docker service"
    systemctl enable docker.service
}

# the lxc caches of the qa tests (610, 611, 015)
. ./lxc-cache.sh

/bin/true
