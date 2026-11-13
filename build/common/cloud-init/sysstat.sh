#!/bin/bash

echo
echo "#####################"
echo "###### SYSSTAT ######"
echo "#####################"
echo

# The image carries sysstat with the collection disabled: enable it on
# the instance. No-op on the images built without sysstat.
[[ -f /etc/default/sysstat ]] || {
    echo "sysstat not installed, skip"
    exit 0
}

rm -f /var/log/sysstat/sa[0-9]* /var/log/sysstat/sar[0-9]*
sed -i -e 's/^ENABLED=.*/ENABLED="true"/' /etc/default/sysstat
systemctl enable sysstat sysstat-collect.timer sysstat-summary.timer
