#!/bin/bash
#
# Install DRBD 9 from the LINBIT customer repository on SLES

[[ ${LINBIT_KEY} == "undefined" ]] && {
    echo "Error: variable LINBIT_KEY is not defined"
    exit 1
}

[[ ! -f /etc/os-release ]] && {
    echo "/etc/os-release not found"
    exit 1
}

. /etc/os-release

typeset -i DISTRO_MAJOR="${VERSION_ID%.*}"
typeset -i DISTRO_MINOR="${VERSION_ID#*.}"

# LINBIT repository names: sles12-sp5, sles15-sp7, sles16.0
if [ ${DISTRO_MAJOR} -ge 16 ]; then
    LINBIT_DIST="sles${VERSION_ID}"
else
    LINBIT_DIST="sles${DISTRO_MAJOR}-sp${DISTRO_MINOR}"
fi

URL="https://packages.linbit.com/public/linbit-keyring.rpm"
OLDURL="https://packages.linbit.com/public/linbit-keyring-with-53B3B037282B6E23.rpm"

# rpm 4.11 can not verify signatures made with a subkey
[ ${DISTRO_MAJOR} -le 12 ] && {
    URL=$OLDURL
}

wget -q -O /dev/shm/linbit-keyring.rpm $URL || {
    echo "Error: could not download Linbit keyring package"
    exit 1
}

rpm -Uvh /dev/shm/linbit-keyring.rpm
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-linbit || exit 1

[[ -f /etc/zypp/repos.d/linbit.repo ]] && rm -f /etc/zypp/repos.d/linbit.repo

cat > /etc/zypp/repos.d/linbit.repo <<EOF
[drbd-9]
name=LINBIT Packages for drbd-9 - ${LINBIT_DIST}
baseurl=https://packages.linbit.com/${LINBIT_KEY}/yum/${LINBIT_DIST}/drbd-9/\$basearch
enabled=1
autorefresh=1
type=rpm-md
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-linbit
gpgcheck=1
repo_gpgcheck=1
priority=90
EOF

zypper --non-interactive refresh drbd-9 || exit 1
zypper --non-interactive install drbd-utils drbd-kmp-default || exit 1

depmod -a
modprobe drbd || exit 1
modinfo drbd | grep ^version
typeset -i DRBD_MAJOR_VER=$(modinfo drbd | grep ^version | awk '{print $2}' | awk -F'.' '{print $1}')
[ ${DRBD_MAJOR_VER} -lt 9 ] && {
    echo "DRBD version error. Expecting 9+, found ${DRBD_MAJOR_VER}"
    exit 1
}

exit 0
