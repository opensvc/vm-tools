#!/bin/bash
# Fill the lxc caches the qa tests use, sourced by the custom script of
# the distribution: the cache of the ubuntu template (test 610) and the
# cache of the download template (tests 611 and 015) of one ubuntu
# release. noble when the debootstrap of the node knows it, jammy
# otherwise: focal and sles15 ship a debootstrap too old for noble.
# A failure fails the build: a node without the cache would download the
# rootfs at test time.

which lxc-create >/dev/null 2>&1 || {
    echo "no lxc-create: no lxc cache"
    return 0
}
which debootstrap >/dev/null 2>&1 || {
    echo "no debootstrap: the ubuntu template can not fill the lxc cache" >&2
    exit 1
}
if [[ -e /usr/share/debootstrap/scripts/noble ]]; then
    LXC_RELEASE=noble
else
    LXC_RELEASE=jammy
fi
echo "Loading LXC cache, ubuntu $LXC_RELEASE"
lxc-create -n dummy1 -t ubuntu -- --release $LXC_RELEASE || {
    echo "lxc ubuntu template failed for $LXC_RELEASE" >&2
    exit 1
}
lxc-create -n dummy2 -t download -- --dist ubuntu --release $LXC_RELEASE --arch amd64 || {
    echo "lxc download template failed for $LXC_RELEASE" >&2
    exit 1
}
lxc-ls
ls -l /var/cache/lxc/
du -sh /var/cache/lxc/
lxc-destroy -n dummy1
lxc-destroy -n dummy2
