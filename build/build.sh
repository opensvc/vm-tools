#!/bin/bash

set -a

#CFG_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
#ROOT=$(cd -- $CFG_DIR/.. &> /dev/null && pwd )

#PACKER_PLUGIN_PATH=$ROOT/packer/plugins
#PACKER_CACHE_DIR=$ROOT/packer/cache

. packer/environment

DISTRO_IMG=$@

for img in $DISTRO_IMG
do
    [[ ! -d $img ]] && continue
    echo "--- building image $img ---"
    PACKER_OPTS=""
    cd $img && {
        rm -rf output-*
        [[ -f $img.secrets.pkrvars.hcl ]] && PACKER_OPTS="$PACKER_OPTS -var-file=$img.secrets.pkrvars.hcl"
        PACKER_LOG=1 packer build $PACKER_OPTS $img.pkr.hcl
        retcode=$?
        if [ $retcode -ne 0 ]; then
            echo "Error during packer image build. Exiting with retcode $retcode"
            exit $retcode
        fi
        [[ -f ./output-custom_image/efivars.fd ]] && {
            echo "Copying UEFI vars $file to /var/lib/libvirt/images/$img.efivars.fd"
            cp ./output-custom_image/efivars.fd /var/lib/libvirt/images/$img.efivars.fd && rm -f ./output-custom_image/efivars.fd
        }
        for file in $(cd ./output-custom_image && ls -1 *.qcow2)
        do
            echo "Copying image $file to KVM_IMAGES_ROOT/$file"
            cp -f ./output-custom_image/$file /var/lib/libvirt/images/ && rm -f ./output-custom_image/$file
        done
        cd -
    }
done

exit 0
