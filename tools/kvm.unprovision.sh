#!/bin/bash

set -a

PATH_SCRIPT="$(cd $(/usr/bin/dirname $(whence -- $0 2>/dev/null|| echo $0));pwd)"
cd $PATH_SCRIPT

. ../configs/environment || exit 1

# $1 vm path
#
# example
# ./kvm.unprovision.sh /data/vms/rhel8/qarh8c18n1

VM_ROOT=$1
VM_NAME=$(basename $VM_ROOT)

for FILE in environment secrets
do
    [[ -f $CONFIGS/machines/$VM_NAME/$FILE ]] && {
        echo "Loading $CONFIGS/machines/$VM_NAME/$FILE custom configuration"
        . $CONFIGS/machines/$VM_NAME/$FILE
    }
done

echo "begin sleep 5 $VM_ROOT" | systemd-cat
sleep 5
echo "end sleep 5 $VM_ROOT" | systemd-cat
echo "begin rm $VM_ROOT" | systemd-cat
[[ ! -z $VM_ROOT ]] && rm -rf $VM_ROOT
echo "end rm $VM_ROOT" | systemd-cat

echo "begin rm logical volumes" | systemd-cat
for lv in root data
do
[[ -L /dev/$VM_STORAGE_LVMVG/${VM_NAME}_${lv} ]] && {
    echo "removing logical volume /dev/$VM_STORAGE_LVMVG/${VM_NAME}_${lv}"
    lvremove -y /dev/$VM_STORAGE_LVMVG/${VM_NAME}_${lv}
}
done
echo "end rm logical volumes" | systemd-cat

echo "begin image gc" | systemd-cat
$TOOLS/image.gc.sh || echo "image gc failed"
echo "end image gc" | systemd-cat
