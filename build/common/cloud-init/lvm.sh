#!/bin/bash

echo
echo "#####################"
echo "######## LVM ########"
echo "#####################"
echo

[[ -f ~opensvc/opensvc-qa.sh ]] && . ~opensvc/opensvc-qa.sh

# vg of the root filesystem, designated by its uuid: a shared lun may carry
# another vg with the same name (ex: a leftover ubuntu-vg)
ROOTDEV=$(findmnt -no SOURCE /)
ROOTVG=$(lvs --noheadings -o vg_name "${ROOTDEV}" 2>/dev/null | tr -d ' ')
ROOTVGUUID=$(lvs --noheadings -o vg_uuid "${ROOTDEV}" 2>/dev/null | tr -d ' ')

grep -q 'use_lvmetad = 1' /etc/lvm/lvm.conf || {
echo "Disable lvmetad"
cp /etc/lvm/lvm.conf /etc/lvm/lvm.conf.preosvc
cat /etc/lvm/lvm.conf.preosvc | sed -e 's/use_lvmetad = 1/use_lvmetad = 0/g' > /etc/lvm/lvm.conf
rm -f /etc/lvm/lvm.conf.preosvc
}

grep -q 'hosttags = 1' /etc/lvm/lvm.conf || {
echo "Enable lvm hosttags parameter"
cat - <<EOF >>/etc/lvm/lvm.conf
tags {
    hosttags = 1
    local {}
}
EOF
}

grep -q volume_list /etc/lvm/lvm_$HOSTNAME.conf >> /dev/null 2>&1 || {
echo "Configure lvm hosttags"
cat - <<EOF >>/etc/lvm/lvm_$HOSTNAME.conf
activation {
    volume_list = ["@local", "@$HOSTNAME"]
}
EOF
}

grep ' / ' /proc/mounts | grep -q btrfs && {
    echo "root filesystem is btrfs type. local tag not needed"
    exit 0
}

# the root vg must be activable with volume_list, else any regenerated
# initramfs (kernel update, fips) can not activate the root lv at boot
if [ -n "${ROOTVGUUID}" ]
then
	echo "Add tag local to rootvg ${ROOTVG} (${ROOTVGUUID})"
	vgchange --addtag local --select "vg_uuid=${ROOTVGUUID}" || exit 1
else
    echo "ROOTVG is empty. Exiting."
    exit 1
fi

if [ -b /dev/vdb ]
then
    echo "Creating data vg on /dev/vdb"
    wipefs -af /dev/vdb
    pvcreate -f /dev/vdb
    vgcreate data /dev/vdb
    vgchange --addtag local data
fi

exit 0
