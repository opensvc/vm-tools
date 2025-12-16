#!/bin/bash

set -a

PATH_SCRIPT="$(cd $(/usr/bin/dirname $(whence -- $0 2>/dev/null|| echo $0));pwd)"
cd $PATH_SCRIPT

. ../configs/environment || exit 1

# $1 hostname
# $2 distrib
# $3 installfolder
#
# example
# ./kvm.provision.sh c2n1 ubuntu22 /data/tmp

VM_NAME=$1
VM_DISTRO=$2
VM_ROOT=$3

VM_BASE_IMAGE="${IMAGES[$VM_DISTRO]}"
VM_DISTRO_KIND="${VM_DISTRO%%+([[:digit:]])}"
VM_CONFIGS="$CONFIGS/machines/$VM_NAME"

# empty if not vdc
NET=$(grep -w ^$VM_NAME ${NODES} | sort -u | awk '{print $4}')
VM_IP=$(grep -w ^$VM_NAME ${NODES} | sort -u | awk '{print $3}')
VM_CID=$(grep -w ^$VM_NAME ${NODES} | sort -u | awk '{print $2}')
VM_2DGCID=$(printf "%02d" "$VM_CID")
VM_HEXCID=$(printf "%02x" "$VM_CID")
NAS_SIP=$(grep -w ^nas ${NODES} | sort -u | awk '{print $3}')
NAS_IP="$NET.0.0.$NAS_SIP"
NFS_IP="$NET.$VM_CID.0.1"

# c1n1 ssh => 20111   vnc => 20161
# c6n2 ssh => 20612   vnc => 20662
VM_SSHPORT=${PORT_FWD[$NET]}$VM_2DGCID$VM_IP
[[ -z "$VM_VNCPORT" ]] && {
    let VM_VNCPORT=$VM_SSHPORT+50
}

for FILE in environment secrets
do
    [[ -f $VM_CONFIGS/$FILE ]] && {
        echo "Loading $VM_CONFIGS/$FILE custom configuration"
        . $VM_CONFIGS/$FILE
    }
done

VM_NIC=${VM_NIC:-eth0}
VM_NIC_MODEL=${VM_NIC_MODEL:-virtio}
VM_AUDIO=${VM_AUDIO:-none}
[[ "$VM_DISTRO" =~ ^debian.* ]] && VM_NIC="enp1s0"
[[ "$VM_DISTRO" =~ ^ubuntu.* ]] && VM_NIC="enp1s0"

VM_DRIVER_CACHE=${VM_DRIVER_CACHE:-none}
VM_DRIVER_IO=${VM_DRIVER_IO:-native}
VM_DRIVER_DISCARD=${VM_DRIVER_DISCARD:-unmap}

VM_BRIDGE=${VM_BRIDGE:-br0}
VM_IPV6_BRIDGE=${VM_IPV6_BRIDGE}
VM_VNCPASSWORD=${VM_VNCPASSWORD:-password}

OSVC_IPV6_VRACK_PREFIX=${OSVC_IPV6_VRACK_PREFIX}

# VM_LINKED_CLONE
# false: vm base image is fully copied into vm filesystem before creating system.qcow2
# true: system.qcow2 is directly backed by shared vm base image (warning: fastest but greater risk)
VM_LINKED_CLONE=${VM_LINKED_CLONE:-false}

# VM_STORAGE_TYPE
# qcow2: vm disks are qcow2 files stored on filesystem
# lvm: vm disks are raw lvm devices presented to vm
VM_STORAGE_TYPE=${VM_STORAGE_TYPE:-qcow2}
VM_STORAGE_LVMVG=${VM_STORAGE_LVMVG}

function check_prerequisites() {
    title Begin:$FUNCNAME
    [[ -z "$VM_NAME" ]] && exiterr "VM_NAME is not defined"
    [[ -z "$VM_DISTRO" ]] && exiterr "VM_DISTRO is not defined"
    [[ -z "$VM_ROOT" ]] && exiterr "VM_ROOT is not defined"
    [[ ! -v "IMAGES[$VM_DISTRO]" ]] && exiterr "VM_DISTRO $VM_DISTRO is not available"
    [[ -z "$VM_SYS_SIZE" ]] && exiterr "VM_SYS_SIZE is not defined"
    [[ -z "$VM_DATA_SIZE" ]] && exiterr "VM_DATA_SIZE is not defined"
    [[ -z "$VM_STORAGE_TYPE" ]] && exiterr "VM_STORAGE_TYPE is not defined"
    [[ $VM_STORAGE_TYPE == "lvm" ]] && {
        [[ $VM_LINKED_CLONE == "true" ]] && exiterr "VM_LINKED_CLONE is not compatible with lvm"
        [[ -z $VM_STORAGE_LVMVG ]] && exiterr "VM_STORAGE_LVMVG is not defined"
    }
    title End:$FUNCNAME
}

function prepare()
{
    title Begin:$FUNCNAME
    [[ ! -d $VM_ROOT ]] && mkdir -p $VM_ROOT
    title End:$FUNCNAME
}

function check_network()
{
    title Begin:$FUNCNAME
    if [ -n "${OSVC_IPV6_VRACK_NET}" ]; then
        [[ ! -n "${OSVC_IPV6_VRACK_PREFIX}" ]] && OSVC_IPV6_VRACK_PREFIX=$(echo $OSVC_IPV6_VRACK_NET | awk -F':' '{printf "%s:%s:%s:%s\n",$1,$2,$3,$4}')
        # identify nic connected to ipv6 net
	NIC=$(ip -j route get $OSVC_IPV6_VRACK_NET | jq -r '.[]|.dev')
	# check if nic is a bridge
	[ -d /sys/class/net/$NIC/bridge ] && {
	    VM_IPV6_BRIDGE=$NIC
            echo "found network $OSVC_IPV6_VRACK_NET reacheable through $VM_IPV6_BRIDGE" 
        }
    fi
    title End:$FUNCNAME
}

function copy_base_image()
{
    title Begin:$FUNCNAME
    [[ ! -f $KVM_IMAGES_ROOT/$VM_BASE_IMAGE ]] && exiterr "kvm image $KVM_IMAGES_ROOT/$VM_BASE_IMAGE not found"
    [[ ! -f $VM_ROOT/$VM_BASE_IMAGE ]] && cp $KVM_IMAGES_ROOT/$VM_BASE_IMAGE $VM_ROOT/$VM_BASE_IMAGE
    title End:$FUNCNAME
}

function create_std_vmdisks()
{
    title Begin:$FUNCNAME
    [[ -f $VM_ROOT/system.qcow2 ]] && exiterr "$VM_ROOT/system.qcow2 already exist"
    qemu-img create -f qcow2 $VM_ROOT/system.qcow2 $VM_SYS_SIZE
    qemu-img create -f qcow2 $VM_ROOT/data.qcow2 $VM_DATA_SIZE
    title End:$FUNCNAME
}

function create_ci_vmdisks()
{
    title Begin:$FUNCNAME
    [[ -f $VM_ROOT/system.qcow2 ]] && exiterr "$VM_ROOT/system.qcow2 already exist"
    [[ -f $VM_ROOT/data.qcow2 ]] && exiterr "$VM_ROOT/data.qcow2 already exist"
    BACKING_FILE="$VM_ROOT/$VM_BASE_IMAGE"
    [[ $VM_LINKED_CLONE == "true" ]] && BACKING_FILE=$KVM_IMAGES_ROOT/$VM_BASE_IMAGE
    echo "Creating system.qcow2 backed by $BACKING_FILE"
    qemu-img create -f qcow2 -F qcow2 -o backing_file=$BACKING_FILE $VM_ROOT/system.qcow2 && \
        qemu-img resize $VM_ROOT/system.qcow2 $VM_SYS_SIZE
    qemu-img create -f qcow2 $VM_ROOT/data.qcow2 $VM_DATA_SIZE
    title End:$FUNCNAME
}

function substitute_patterns()
{
    title Begin:$FUNCNAME 

    local FILES="$VM_ROOT/meta-data $VM_ROOT/user-data $VM_ROOT/network-config"

    sed -i "s@VM_NAME@$VM_NAME@g" $FILES
    sed -i "s@VM_NIC@$VM_NIC@g" $FILES
    sed -i "s@VM_HEXCID@$VM_HEXCID@g" $FILES
    sed -i "s@VM_2DGCID@$VM_2DGCID@g" $FILES
    sed -i "s@VM_CID@$VM_CID@g" $FILES
    sed -i "s@VM_NET@$NET@g" $FILES
    sed -i "s@VM_IP@$VM_IP@g" $FILES
    sed -i "s@OSVC_IPV6_VRACK_NET@$OSVC_IPV6_VRACK_NET@g" $FILES
    sed -i "s@OSVC_IPV6_VRACK_PREFIX@$OSVC_IPV6_VRACK_PREFIX@g" $FILES
    sed -i "s@NAS_IP@$NAS_IP@g" $FILES
    sed -i "s@NFS_IP@$NFS_IP@g" $FILES
    sed -i "s@RH_ORG_ID@$RH_ORG_ID@g" $FILES
    sed -i "s@RH_ACTIVATION_KEY@$RH_ACTIVATION_KEY@g" $FILES
    sed -i "s/SUSE_ORGANISATION_MAIL/$SUSE_ORGANISATION_MAIL/g" $FILES
    sed -i "s@SUSE_REGISTRATION_KEY@$SUSE_REGISTRATION_KEY@g" $FILES
    title End:$FUNCNAME
}

function gen_cloud_init_files()
{
    title Begin:$FUNCNAME 
    local CUSTOMIZE_META_DATA=true
    local CUSTOMIZE_USER_DATA=true
    local CUSTOMIZE_NETWORK_CONFIG=true
    
    # custom meta-data
    [[ -f $VM_CONFIGS/meta-data ]] && {
            cp -f $VM_CONFIGS/meta-data $VM_ROOT/
            CUSTOMIZE_META_DATA=false
    }

    # custom user-data
    [[ -f $VM_CONFIGS/user-data ]] && {
            cp -f $VM_CONFIGS/user-data $VM_ROOT/
            CUSTOMIZE_USER_DATA=false
    }

    [[ -f $VM_CONFIGS/network-config ]] && {
            cp -f $VM_CONFIGS/network-config $VM_ROOT/
            CUSTOMIZE_NETWORK_CONFIG=false
    }

    if [ "$CUSTOMIZE_META_DATA" = true ] ; then
        cp -f $TEMPLATES/meta-data.common $VM_ROOT/meta-data
	[[ "$VM_DISTRO" =~ ^rhel7.* ]] && cp -f $TEMPLATES/meta-data.common.v1 $VM_ROOT/meta-data
    fi

    if [ "$CUSTOMIZE_USER_DATA" = true ] ; then
        cp -f $TEMPLATES/user-data.common $VM_ROOT/user-data
        for SECTION in write_files run_cmd
        do
            cat $TEMPLATES/user-data.$SECTION.$VM_DISTRO >> $VM_ROOT/user-data
        done
	echo >> $VM_ROOT/user-data
    fi

    if [ "$CUSTOMIZE_NETWORK_CONFIG" = true ] ; then
	[[ "$VM_DISTRO" =~ ^sles16.* ]] && cp -f $TEMPLATES/network-config.sles16 $VM_ROOT/network-config
    fi

    [[ -f $VM_CONFIGS/cloud-init.host.ssh_keys ]] && {
	    cat $VM_CONFIGS/cloud-init.host.ssh_keys >> $VM_ROOT/user-data
    }

    substitute_patterns
    title End:$FUNCNAME
}

function create_seed() {
	title Begin:$FUNCNAME
    SEED_OPTS=""
    gen_cloud_init_files
    test -f $VM_ROOT/network-config && SEED_OPTS="$VM_ROOT/network-config"
    genisoimage -input-charset utf-8 -output $VM_ROOT/seed.iso -volid cidata -joliet -rock $VM_ROOT/user-data $VM_ROOT/meta-data $SEED_OPTS || \
        exiterr "error while creating seed.iso"
    title End:$FUNCNAME
}

function create_uefi() {
    title Begin:$FUNCNAME
    # UEFI based images
    [[ "$VM_BASE_IMAGE" =~ .*uefi.* ]] && {
        UEFI_SECURE_LOADER=${UEFI_SECURE_LOADER:-no}
        UEFI_LOADER="${UEFI_LOADER}"
        [[ -z "$UEFI_LOADER" ]] && {
            # no loader definition set in VM_CONFIGS
            [[ -f $VM_ROOT/uefi.loader.fd ]] && {
                UEFI_LOADER="$VM_ROOT/uefi.loader.fd"
            } || {
                UEFI_LOADER="/usr/share/OVMF/OVMF_CODE_4M.fd"
            }
        }
    
        UEFI_VARS="${UEFI_VARS}"
        [[ -z "$UEFI_VARS" ]] && {
            # no vars definition set in VM_CONFIGS
	    [[ -f $KVM_IMAGES_ROOT/$VM_DISTRO.efivars.fd ]] && {
                echo "Copying $KVM_IMAGES_ROOT/$VM_DISTRO.efivars.fd to $VM_ROOT/uefi.vars.fd"
	        cp $KVM_IMAGES_ROOT/$VM_DISTRO.efivars.fd $VM_ROOT/uefi.vars.fd
	    }
            [[ -f $VM_ROOT/uefi.vars.fd ]] && {
                UEFI_VARS="$VM_ROOT/uefi.vars.fd"
            } || {
                UEFI_VARS="/usr/share/OVMF/OVMF_VARS_4M.fd"
            }
        }
        VM_VIRTINSTALL_OPTS="${VM_VIRTINSTALL_OPTS} --boot loader=$UEFI_LOADER,loader.readonly=yes,loader.type=pflash,nvram.template=$UEFI_VARS,loader_secure=$UEFI_SECURE_LOADER,bootmenu.enable=on,bios.useserial=on"
    } || echo "non uefi image"

    title End:$FUNCNAME
}

function execute_virtinstall()
{
	title Begin:$FUNCNAME
	VM_CPU=${VM_CPU:-2}
	VM_RAM=${VM_RAM:-2048}
    VM_OSVARIANT=$(get_kvm_osvariant)
	VM_CONSOLE_KEYMAP=${VM_CONSOLE_KEYMAP:-fr}
	VM_VIRTINSTALL_OPTS=${VM_VIRTINSTALL_OPTS}
    
    grep -w ^$VM_NAME ${NODES} 2>/dev/null && {
        # found vdc mac addresses
        # we have to connect 3 nics
        VM_VIRTINSTALL_OPTS="${VM_VIRTINSTALL_OPTS} --network=bridge:br-$VM_CID-0,model=$VM_NIC_MODEL,mac=22:23:24:$VM_HEXCID:00:$VM_IP"
        VM_VIRTINSTALL_OPTS="${VM_VIRTINSTALL_OPTS} --network=bridge:br-$VM_CID-1,model=$VM_NIC_MODEL,mac=22:23:24:$VM_HEXCID:01:$VM_IP"
        VM_VIRTINSTALL_OPTS="${VM_VIRTINSTALL_OPTS} --network=bridge:br-$VM_CID-2,model=$VM_NIC_MODEL,mac=22:23:24:$VM_HEXCID:02:$VM_IP"
	# if an ipv6 bridged connectivity has been found, add a nic connected to it
        if [ ! -z "${VM_IPV6_BRIDGE}" ]; then
            VM_VIRTINSTALL_OPTS="${VM_VIRTINSTALL_OPTS} --network=bridge:${VM_IPV6_BRIDGE},model=$VM_NIC_MODEL,mac=22:23:24:$VM_HEXCID:60:$VM_IP"
	fi

	# netplan training
	if [[ $VM_NAME =~ c[1-9]n3 ]]; then
	    num=$(($VM_IP + 10))
            VM_VIRTINSTALL_OPTS="${VM_VIRTINSTALL_OPTS} --network=bridge:br-$VM_CID-2,model=$VM_NIC_MODEL,mac=22:23:24:$VM_HEXCID:02:$num"
        fi
    } || {
        # standard cnx
        VM_VIRTINSTALL_OPTS="${VM_VIRTINSTALL_OPTS} --network=bridge:$VM_BRIDGE,model=virtio"
    }

    [[ "$VM_BASE_IMAGE" =~ .*\.qcow2 ]] && VM_VIRTINSTALL_OPTS="${VM_VIRTINSTALL_OPTS} --import"
    [[ "$UEFI_SECURE_LOADER" =~ yes ]] && VM_VIRTINSTALL_OPTS="${VM_VIRTINSTALL_OPTS} --machine q35 --features smm.state=on"
    echo "$VM_BASE_IMAGE" | grep -qEi "microsoft|windows" && {
        [[ -f $KVM_IMAGES_ROOT/virtio-win.iso ]] && {
	    VM_VIRTINSTALL_OPTS="${VM_VIRTINSTALL_OPTS} --disk $KVM_IMAGES_ROOT/virtio-win.iso,device=cdrom"
        }
    }
	
    echo virt-install \
    --connect qemu:///system \
    --audio $VM_AUDIO \
    --graphics vnc,keymap=$VM_CONSOLE_KEYMAP,listen=0.0.0.0,port=$VM_VNCPORT,password=$VM_VNCPASSWORD \
    --virt-type kvm \
    --name $VM_NAME \
    --ram $VM_RAM \
    --vcpus=$VM_CPU \
    --os-variant $VM_OSVARIANT \
    --iothreads 1 \
    --noautoconsole \
    --console pty,target_type=serial,log.file=$VM_ROOT/console.log $VM_VIRTINSTALL_OPTS

    virt-install \
    --connect qemu:///system \
    --audio $VM_AUDIO \
    --graphics vnc,keymap=$VM_CONSOLE_KEYMAP,listen=0.0.0.0,port=$VM_VNCPORT,password=$VM_VNCPASSWORD \
    --virt-type kvm \
    --name $VM_NAME \
    --ram $VM_RAM \
    --vcpus=$VM_CPU \
    --os-variant $VM_OSVARIANT \
    --iothreads 1 \
    --noautoconsole \
    --console pty,target_type=serial,log.file=$VM_ROOT/console.log $VM_VIRTINSTALL_OPTS
    title End:$FUNCNAME
}

# begin

check_prerequisites
check_network
prepare

[[ $VM_STORAGE_TYPE == "lvm" ]] && {
    ROOT_LV_SIZE_BYTES=$(qemu-img info $KVM_IMAGES_ROOT/$VM_BASE_IMAGE | grep -oP '(?<=\().*(?=bytes\))')
    ROOT_LV_SIZE_MBYTES=$(echo "scale=0;$ROOT_LV_SIZE_BYTES/1048576" | bc -l)

    typeset -i done=0
    check_vg_space $VM_STORAGE_LVMVG ${ROOT_LV_SIZE_MBYTES}m && \
	    lvcreate -y -L${ROOT_LV_SIZE_MBYTES}m -n ${VM_NAME}_root $VM_STORAGE_LVMVG && \
	    lvextend -y -L+10m /dev/$VM_STORAGE_LVMVG/${VM_NAME}_root && \
	    ((done++))
    check_vg_space $VM_STORAGE_LVMVG $VM_DATA_SIZE && \
	    lvcreate -y -L$VM_DATA_SIZE -n ${VM_NAME}_data $VM_STORAGE_LVMVG && \
	    ((done++))
    [[ $done -ne 2 ]] && {
        echo "error during lvm volume creation. exiting"
        lvremove -y /dev/$VM_STORAGE_LVMVG/${VM_NAME}_data >> /dev/null 2>&1
        lvremove -y /dev/$VM_STORAGE_LVMVG/${VM_NAME}_root >> /dev/null 2>&1
    }
    VM_VIRTINSTALL_OPTS="$VM_VIRTINSTALL_OPTS --disk path=/dev/$VM_STORAGE_LVMVG/${VM_NAME}_root,driver.iothread=1 --disk path=/dev/$VM_STORAGE_LVMVG/${VM_NAME}_data,driver.iothread=1 --disk $VM_ROOT/seed.iso,device=cdrom"
    echo "Dumping image $KVM_IMAGES_ROOT/$VM_BASE_IMAGE into lvm lv /dev/$VM_STORAGE_LVMVG/${VM_NAME}_root"
    time qemu-img dd -f qcow2 -O raw if=$KVM_IMAGES_ROOT/$VM_BASE_IMAGE of=/dev/$VM_STORAGE_LVMVG/${VM_NAME}_root bs=1M
}

# driver.queues=nb_vcpu no impact with qcow2|lvm
# driver.iothread=1 lvm gain de 30 secondes sur 1h07m de reference
# driver.iothread=1 qcow2 gain de 60 secondes sur 1h07m de reference

[[ $VM_STORAGE_TYPE == "qcow2" ]] && {
    grep -w ^$VM_NAME ${NODES} 2>/dev/null && {
        [[ $VM_LINKED_CLONE == "false" ]] && copy_base_image
        create_ci_vmdisks
        #VM_VIRTINSTALL_OPTS="$VM_VIRTINSTALL_OPTS --disk path=$VM_ROOT/system.qcow2,format=qcow2,driver.io=threads,driver.cache=writeback --disk path=$VM_ROOT/data.qcow2,format=qcow2,driver.io=threads,driver.cache=writeback --disk $VM_ROOT/seed.iso,device=cdrom"
        #VM_VIRTINSTALL_OPTS="$VM_VIRTINSTALL_OPTS --disk path=$VM_ROOT/system.qcow2,format=qcow2,driver.iothread=1 --disk path=$VM_ROOT/data.qcow2,format=qcow2,driver.iothread=1 --disk $VM_ROOT/seed.iso,device=cdrom"
        VM_VIRTINSTALL_OPTS="$VM_VIRTINSTALL_OPTS --disk path=$VM_ROOT/system.qcow2,format=qcow2,driver.cache=${VM_DRIVER_CACHE},driver.io=${VM_DRIVER_IO},driver.discard=${VM_DRIVER_DISCARD} --disk path=$VM_ROOT/data.qcow2,format=qcow2,driver.cache=${VM_DRIVER_CACHE},driver.io=${VM_DRIVER_IO},driver.discard=${VM_DRIVER_DISCARD} --disk $VM_ROOT/seed.iso,device=cdrom"
    } || {
        create_std_vmdisks
        VM_VIRTINSTALL_OPTS="$VM_VIRTINSTALL_OPTS --disk path=$VM_ROOT/system.qcow2,format=qcow2,driver.cache=${VM_DRIVER_CACHE},driver.io=${VM_DRIVER_IO},driver.discard=${VM_DRIVER_DISCARD} --disk path=$VM_ROOT/data.qcow2,format=qcow2,driver.cache=${VM_DRIVER_CACHE},driver.io=${VM_DRIVER_IO},driver.discard=${VM_DRIVER_DISCARD} --cdrom $KVM_IMAGES_ROOT/$VM_BASE_IMAGE"
    }
}
create_seed
create_uefi
execute_virtinstall
