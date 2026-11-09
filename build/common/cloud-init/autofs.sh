#!/bin/bash

echo
echo "####################"
echo "###### AUTOFS ######"
echo "####################"
echo

[[ -f ~opensvc/opensvc-qa.sh ]] && . ~opensvc/opensvc-qa.sh

NFSSRV=${TGT}

[[ -z ${NFSSRV} ]] && {
    echo "Error : NFSSRV not found in environment"
    exit 1
}

[[ ! -d /etc/auto.master.d ]] && mkdir -p /etc/auto.master.d
[[ ! -d /nfs ]] && mkdir /nfs

cat - <<EOF >|/etc/auto.master.d/nfs.autofs
/nfs   /etc/auto.nfsshare     --ghost,--timeout=30
EOF

# NFS 4.1, not 4.2: the server-side COPY of 4.2, which cp uses through
# copy_file_range between two files of the share, hangs on the nfsd of the
# ubuntu 26.04 hypervisors kernel 7.0.0-43 (the file created, no data
# written). 4.1 has no COPY: the client copies the data.
cat - <<EOF >|/etc/auto.nfsshare
data -fstype=nfs,vers=4.1,rw,soft,actimeo=2,rsize=8192,wsize=8192   ${NFSSRV}:/data/nfsshare
EOF

grep -q "^#+dir:/etc/auto.master.d" /etc/auto.master && {
    echo "Enabling automount /etc/auto.master.d directory"
    sed -i -e "s/^#+dir:\/etc\/auto.master.d/+dir:\/etc\/auto.master.d/" /etc/auto.master
}

for unit in autofs
do
    systemctl cat $unit >> /dev/null 2>&1 && {
	echo "Found unit $unit"
        systemctl -q is-enabled $unit || {
	    echo "Enabling unit $unit"
	    systemctl -q enable $unit
        }
	echo "Starting unit $unit"
	systemctl restart $unit
    }
done

exit 0
