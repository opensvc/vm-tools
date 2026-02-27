#!/bin/bash

# enable serial console
[[ -f /etc/default/grub ]] && {
    cp /etc/default/grub /etc/default/grub.osvcpacker
    # https://access.redhat.com/articles/7212
    kopts=$(grub2-editenv - list | grep kernelopts)
    echo $kopts | grep -q 'console=tty0 console=ttyS0,115200n8' || {
	    grub2-editenv - set "$kopts console=tty0 console=ttyS0,115200n8"
    }
    sed -i 's/GRUB_TERMINAL_OUTPUT="console"/GRUB_TERMINAL_OUTPUT="console serial"/g' /etc/default/grub
    # better to keep the line below
    grep -q '^GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub || echo 'GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200n8"' >> /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg || exit 1
    grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg || exit 1
}
