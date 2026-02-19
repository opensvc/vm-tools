#!/bin/bash
#
#

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


[[ -f /etc/yum.repos.d/linbit.repo ]] && rm -f /etc/yum.repos.d/linbit.repo

URL="https://packages.linbit.com/public/linbit-keyring.rpm"
OLDURL="https://packages.linbit.com/public/linbit-keyring-with-53B3B037282B6E23.rpm"

[ ${DISTRO_MAJOR} -le 7 ] && {
	URL=$OLDURL
}

wget -q -O /dev/shm/linbit-keyring.rpm $URL || {
    echo "Error: could not download Linbit keyring package"
    exit 1
}

rpm -Uvh /dev/shm/linbit-keyring.rpm

cat > /etc/yum.repos.d/linbit.repo <<EOF
[drbd-9.0]
name=LINBIT Packages for drbd-9.0 - \$basearch
baseurl=https://packages.linbit.com/${LINBIT_KEY}/yum/rhel${DISTRO_MAJOR}.${DISTRO_MINOR}/drbd-9.0/\$basearch
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-linbit
gpgcheck=1
repo_gpgcheck=1
priority=90

[drbd-9]
name=LINBIT Packages for drbd-9 - \$basearch
baseurl=https://packages.linbit.com/${LINBIT_KEY}/yum/rhel${DISTRO_MAJOR}.${DISTRO_MINOR}/drbd-9/\$basearch
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-linbit
gpgcheck=1
repo_gpgcheck=1
priority=90
EOF

PKGUTIL="dnf"
which dnf >>/dev/null 2>&1 || PKGUTIL="yum"

$PKGUTIL -y repolist
$PKGUTIL -y install drbd-utils kmod-drbd

modprobe drbd || exit 1
modinfo drbd | grep ^version
typeset -i DRBD_MAJOR_VER=$(modinfo drbd | grep ^version | awk '{print $2}' | awk -F'.' '{print $1}')
[ ${DRBD_MAJOR_VER} -lt 9 ] && {
    echo "DRBD version error. Expecting 9+, found ${DRBD_MAJOR_VER}"
    exit 1
}

exit 0
