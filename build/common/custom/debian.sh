#!/bin/bash

[[ -f /etc/default/grub ]] && {
    cp /etc/default/grub /etc/default/grub.osvcpacker
    sed -i 's#^GRUB_CMDLINE_LINUX_DEFAULT=.*$#GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200n8"#' /etc/default/grub
    update-grub || exit 1
}

# the lxc cache of the qa test 015, with the dependencies of the agent
. ./lxc-cache-debian.sh

/bin/true
