#!/bin/bash
#

# filter is the cluster id integer to filter on
FILTER=$1
ECHO=echo
CLUSTERS=""
TARGETS_PER_NODE=2
DISKS_PER_CLUSTER=10
SIZE=1G
VDCNODES="/opt/vm-tools/configs/vdc.nodes"
DISKS_ROOT=/var/iscsi

ARRAY="targetcli"

function hinit() {
	[[ -f /tmp/hashmap.$1 ]] && rm -f /tmp/hashmap.$1*
}

function hput() {
	hash=$1
	shift
	key="$1"
	shift
	val="$@"
	previous=""
	[[ -f /tmp/hashmap.$hash ]] && {
		previous=$(grep "^$key " /tmp/hashmap.$hash | awk '{for (i=2; i<=NF; i++) printf $i " " };')
		cp /tmp/hashmap.$hash /tmp/hashmap.$hash.bck
		cat /tmp/hashmap.$hash.bck | grep -v "^$key " >/tmp/hashmap.$hash
	}
	echo "$key $previous $val" >>/tmp/hashmap.$hash
}

function hget() {
	key=$2
	grep "^$key " /tmp/hashmap.$1 | awk '{ for (i=2; i<=NF; i++) printf $i " "};'
	echo
}

function is_sunos() {
	key=$1
		grep "^$key " /tmp/hashmap.clusters | grep -qE "labsol|qasol" && return 0
	return 1
}

function niq {
	echo iqn.2009-11.com.opensvc.srv:$1.storage.initiator
}

function tiq {
	echo iqn.2009-11.com.opensvc.srv:$1.storage.target.$2
}

function diq {
	echo c$1_disk$2
}

function istarget {
	local tgt=$1
	[[ -d /sys/kernel/config/target/iscsi/${tgt} ]] && return 0
	return 1
}

function adddisk {
	local disk=$1
	local size=$2
	local fname="${DISKS_ROOT}/${disk}.img"
	local bstore="/sys/kernel/config/target/core/fileio*/${disk}"
	[[ ! -f ${fname} ]] && $ECHO truncate -s ${size} ${fname}
	[[ ! -d $(echo ${bstore}) ]] && $ECHO $ARRAY /backstores/fileio create ${disk} ${fname}
}

function addacl {
	local tgt=$1
	local iqn=$2
	local aclpath="/sys/kernel/config/target/iscsi/${tgt}/tpgt_1/acls/${iqn}"
	[[ ! -d ${aclpath} ]] && {
		$ECHO $ARRAY /iscsi/${tgt}/tpg1/acls create ${iqn}
	}
}

function mapdisk {
	local tgt=$1
	local disk=$2
	local lun=$3
	local fname="${DISKS_ROOT}/${disk}.img"
	local bstore="/sys/kernel/config/target/core/fileio_0/${disk}"
	# test if already mapped
	[[ -d /sys/kernel/config/target/iscsi/${tgt}/tpgt_1/lun/lun_${lun} ]] && {
		local used=$(find /sys/kernel/config/target/iscsi/${tgt}/tpgt_1/lun/lun_${lun} -type l | xargs -I tutu cat tutu/udev_path)
		if [[ $used =~ "${ROOT_DISKS}/${disk}.img" ]]; then
			echo "# disk ${disk} is already mapped on ${tgt} lun ${lun}"
			return
		else
			echo "# conflict. backstore ${used} is mapped on ${tgt} lun ${lun}"
			exit 1
		fi

	}
	$ECHO $ARRAY /iscsi/${tgt}/tpg1/luns create /backstores/fileio/${disk} lun=${lun}
}

[[ ! -f $VDCNODES ]] && {
	echo "$VDCNODES not found. exiting"
	exit 1
}

[[ ! -d $DISKS_ROOT ]] && mkdir -p $DISKS_ROOT

hinit clusters

cp ${VDCNODES} ${VDCNODES}.nas

if [ -n "$FILTER" ]; then
	cat ${VDCNODES} | awk -v cid=${FILTER} '$2 == cid {print}' >|${VDCNODES}.nas
fi

cat $VDCNODES.nas | grep -Ev "^#|igw|vip|zone|envoy|svc|lxc|kvm|dck|collector|cname" | while read node clusterid ip; do
	hput clusters $clusterid $node
done

CLUSTERS=$(cat /tmp/hashmap.clusters | grep -v ^0 | awk '{printf "%s ", $1}')

# create targets
for c in $CLUSTERS; do
	for n in $(hget clusters $c); do
		for t in $(seq 1 $TARGETS_PER_NODE); do
			target=$(tiq $n $t)
			istarget "$target" || $ECHO $ARRAY /iscsi create $target
		done
	done
done

# global quorum lun=30
adddisk global_diskq 128m

for c in $CLUSTERS; do
	# shared luns for lxc scenarios
	adddisk $(diq $c "_lxc1") 3G
	adddisk $(diq $c "_lxc2") 3G

	# luns for kvm scenarios
	adddisk $(diq $c "_kvm1") 20G
	adddisk $(diq $c "_kvm2") 20G

	# lun for the disk heartbeat scenarios, private to the cluster (the
	# global_diskq is shared by the clusters of the hypervisor)
	adddisk $(diq $c "_hb1") 128m

	# luns for mdadm scenarios
	adddisk $(diq $c "_md1") 16m
	adddisk $(diq $c "_md2") 16m
	adddisk $(diq $c "_md3") 16m
	adddisk $(diq $c "_md4") 16m

	is_sunos $c && {
		for n in $(hget clusters $c); do
			# local node zonepath sol11 and sol10
			for z in $(seq 0 1); do
				adddisk $(diq $c "_zone_${n}_${z}") 8G
			done
			for z in $(seq 2 3); do
				adddisk $(diq $c "_zone_${n}_${z}") 250M
			done
		done

		# failover storage
		for z in $(seq 0 1); do
			adddisk $(diq $c "_zone_shared_$z") 250M
		done
	}

	for n in $(hget clusters $c); do
		for t in $(seq 1 $TARGETS_PER_NODE); do
			addacl $(tiq $n $t) $(niq $n)
			mapdisk $(tiq $n $t) global_diskq 30
			mapdisk $(tiq $n $t) $(diq $c "_hb1") 31
			mapdisk $(tiq $n $t) $(diq $c "_lxc1") 40
			mapdisk $(tiq $n $t) $(diq $c "_lxc2") 41
			mapdisk $(tiq $n $t) $(diq $c "_md1") 42
			mapdisk $(tiq $n $t) $(diq $c "_md2") 43
			mapdisk $(tiq $n $t) $(diq $c "_md3") 44
			mapdisk $(tiq $n $t) $(diq $c "_md4") 45
			mapdisk $(tiq $n $t) $(diq $c "_kvm1") 60
			mapdisk $(tiq $n $t) $(diq $c "_kvm2") 61
			is_sunos $c && {
				# Lun id 70, 71 for local zone path (flex zone)
				# Lun id 72, 73 for local zpool (flex storage)
				for z in $(seq 0 3); do
					mapdisk $(tiq $n $t) $(diq $c "_zone_${n}_${z}") 7$z
				done

				# Lun id 80, 81 for failover zpool storage
				for z in $(seq 0 1); do
					mapdisk $(tiq $n $t) $(diq $c "_zone_shared_$z") 8$z
				done
			}
		done
	done

	for d in $(seq 1 $DISKS_PER_CLUSTER); do
		# data disks
		adddisk $(diq $c $d) $SIZE

		for n in $(hget clusters $c); do
			for t in $(seq 1 $TARGETS_PER_NODE); do
				mapdisk $(tiq $n $t) $(diq $c $d) $d
			done
		done

	done
done

# the commands above change the running configuration only: save it, for the
# luns to come back at the next boot
$ECHO $ARRAY saveconfig
