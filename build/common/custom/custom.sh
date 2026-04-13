#!/bin/bash

set -a
set -x

[[ ! -f /etc/os-release ]] && exit 1

echo "--- Running Custom Scripts ---"

. /etc/os-release

[[ ! -d /opt/vm-tools/build/common/custom ]] && {
	echo "Custom scripts not found in /opt/vm-tools"
	exit 1
}

cd /opt/vm-tools/build/common/custom

OS_FAMILLY=$(uname -s)

for item in $OS_FAMILLY $ID
do
    [[ -x $item.sh ]] && {
	echo "--- $item.sh ---"
        . $item.sh
    }
done

MAJOR_VERSION="${VERSION_ID%.*}"
MINOR_VERSION="${VERSION_ID#*.}"

[[ -x $ID.$MAJOR_VERSION.sh ]] && {
	echo "--- $ID.$MAJOR_VERSION.sh ---"
        . $ID.$MAJOR_VERSION.sh
}

[[ -x $ID.$MAJOR_VERSION.$MINOR_VERSION.sh ]] && {
	echo "--- $ID.$MAJOR_VERSION.$MINOR_VERSION.sh ---"
        . $ID.$MAJOR_VERSION.$MINOR_VERSION.sh
}

exit 0
