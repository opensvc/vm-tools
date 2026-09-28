#!/bin/bash

echo
echo "########################"
echo "######## CUSTOM ########"
echo "########################"
echo

[[ -f ~opensvc/opensvc-qa.sh ]] && . ~opensvc/opensvc-qa.sh

test -x /nfs/data/archives/bin/hl && {
    echo "Copy hl binary to /usr/local/bin"
    cp /nfs/data/archives/bin/hl /usr/local/bin/hl
}

# drbd tunables
cat >| /etc/sysctl.d/98-opensvc-net.conf <<EOF
net.core.rmem_max=2097152
net.core.rmem_default=2097152
net.core.wmem_max=2097152
net.core.wmem_default=2097152
EOF

# ipv6 tunables
# makes ipv6 addr ping as soon as they are configured
cat >| /etc/sysctl.d/97-opensvc-ipv6.conf <<EOF
net.ipv6.conf.all.ndisc_notify = 1
net.ipv6.conf.default.ndisc_notify = 1
EOF

# systemd-resolved tunables
# disable LLMNR and mDNS
mkdir -p /etc/systemd/resolved.conf.d
cat >| /etc/systemd/resolved.conf.d/99-opensvc-no-llmnr-mdns.conf <<EOF
[Resolve]
LLMNR=no
MulticastDNS=no
EOF

exit 0
