#!/bin/bash

set -a

MAJOR_VERSION=$(grep ^VERSION_ID /etc/os-release | awk -F= '{print $2}' | sed -e 's/"//g' | awk -F. '{print $1}')
OS_ID=$(grep ^ID= /etc/os-release | awk -F= '{print $2}' | sed -e 's/"//g')

echo '==> Updating Red Hat packages'

[[ ${MAJOR_VERSION} -eq 7 ]] && [[ ${OS_ID} == "rhel" ]] && {
    yum -y update
    echo '==> Packages Successfully updated'
    exit 0
}

dnf -y update redhat-release

dnf -y update

echo '==> Packages Successfully updated'
exit 0
