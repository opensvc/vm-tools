#!/bin/bash

echo
echo "#######################"
echo "######## ISCSI ########"
echo "#######################"
echo

[[ -f ~opensvc/opensvc-qa.sh ]] && . ~opensvc/opensvc-qa.sh

ISCSITGTIP=${TGT}

[[  -z "$ISCSITGTIP" ]] && {
    ISCSITGTIP=$(getent hosts truenas|awk '{print $1}')
}

[[ -z ${ISCSITGTIP} ]] && {
    echo "Error : ISCSITGTIP not found in environment"
    exit 1
}

ping -q -w 1 ${ISCSITGTIP} >> /dev/null 2>&1 || {
	echo "Error : ISCSITGTIP ${ISCSITGTIP} is not available"
        exit 1
}

which iscsiadm >> /dev/null 2>&1 || {
	echo "error: iscsiadm not found"
        exit 1
}

echo "Creating /etc/multipath.conf"
cat - <<EOF >|/etc/multipath.conf
defaults {
        find_multipaths yes
        user_friendly_names no
}

blacklist {
        devnode "^drbd[0-9]"
        device {
                vendor "VBOX"
                product "HARDDISK"
        }
}

blacklist_exceptions {
        device {
                vendor "FreeNAS"
                product "iSCSI Disk"
        }
        device {
                vendor "TrueNAS"
                product "iSCSI Disk"
        }
}
EOF

cp /etc/multipath.conf /etc/multipath.conf.sgpersist

cat - <<EOF >|/etc/multipath.conf.mpathpersist
defaults {
        find_multipaths yes
        user_friendly_names no
        reservation_key file
}

blacklist {
        devnode "^drbd[0-9]"
        device {
                vendor "VBOX"
                product "HARDDISK"
        }
}

blacklist_exceptions {
        device {
                vendor "FreeNAS"
                product "iSCSI Disk"
        }
        device {
                vendor "TrueNAS"
                product "iSCSI Disk"
        }
}
EOF

systemctl -q is-enabled multipathd.service || {
    echo "Enabling multipathd systemd unit"
    systemctl enable multipathd.service
}

echo "Creating /etc/iscsi/initiatorname.iscsi"
cat - <<EOF >|/etc/iscsi/initiatorname.iscsi
InitiatorName=iqn.2009-11.com.opensvc.srv:$HOSTNAME.storage.initiator
EOF

echo "Enabling automatic restart at boot"
sed -i 's/^node.startup.*$/node.startup = automatic/' /etc/iscsi/iscsid.conf
grep -q 'node.startup = automatic' /etc/iscsi/iscsid.conf || { 
	echo 'node.startup = automatic' >> /etc/iscsi/iscsid.conf
}

systemctl -q is-enabled remote-fs.target || {
    systemctl enable remote-fs.target
}

systemctl -q is-enabled iscsi.service || {
    systemctl enable iscsi.service
    systemctl start iscsi.service
}

iscsiadm -m discovery -t st -p $ISCSITGTIP && {
    iscsiadm  -m node | grep -w $HOSTNAME | awk '{print $2}' | xargs -n 1 iscsiadm -m node --login --targetname
    # the discovery records the targets of every node of the nas, with
    # node.startup = automatic: only ours may stay automatic, the nas acl
    # rejects the others and open-iscsi.service fails at each boot
    iscsiadm -m node | grep -vw $HOSTNAME | awk '{print $2}' | while read TARGET; do
        iscsiadm -m node --targetname $TARGET -o update -n node.startup -v manual
    done
}

exit 0
