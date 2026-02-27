#!/bin/bash

# enable serial console
[[ -f /etc/default/grub ]] && {
    cp /etc/default/grub /etc/default/grub.osvcpacker
    # https://access.redhat.com/articles/7212
    grubby --update-kernel=ALL --args="console=tty0 console=ttyS0,115200"
    grubby --info DEFAULT
    sed -i 's/GRUB_TERMINAL_OUTPUT="console"/GRUB_TERMINAL_OUTPUT="console serial"/g' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
    grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
}
