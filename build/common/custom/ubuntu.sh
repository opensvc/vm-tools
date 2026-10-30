#!/bin/bash

[[ -f /etc/default/grub ]] && {
    cp /etc/default/grub /etc/default/grub.osvcpacker
    sed -i 's#^GRUB_CMDLINE_LINUX_DEFAULT=.*$#GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200n8"#' /etc/default/grub
    grep -q '^GRUB_TERMINAL=' /etc/default/grub || echo 'GRUB_TERMINAL="console serial"' >> /etc/default/grub
    sed -i 's/GRUB_TIMEOUT_STYLE=hidden/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub
    sed -i 's/GRUB_TIMEOUT=0/GRUB_TIMEOUT=3/' /etc/default/grub
    update-grub || exit 1
}

for file in /etc/cloud/cloud.cfg.d/99-installer.cfg /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg
do
    [[ -f $file ]] && {
        echo "removing $file"
        rm -f $file
    }
done

which lxc-create >> /dev/null 2>&1 && {
	echo "Loading LXC cache"
    lxc-create -n dummy1 -t ubuntu -- --release jammy
    lxc-create -n dummy2 -t ubuntu -- --release noble
    # The ubuntu template can not make an unprivileged container: the qa
    # tests use the download template, from its cache with --force-cache.
    lxc-create -n dummy3 -t download -- --dist ubuntu --release jammy --arch amd64
    lxc-ls
    ls -l /var/cache/lxc/
    du -sh /var/cache/lxc/
    lxc-destroy dummy1 ; lxc-destroy dummy2 ; lxc-destroy dummy3
}

[[ ! -d /etc/apparmor.d/disable ]] && mkdir -p /etc/apparmor.d/disable
[[ -f /etc/apparmor.d/runc ]] && ln -s /etc/apparmor.d/runc /etc/apparmor.d/disable/

/bin/true
