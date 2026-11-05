#!/bin/bash
# Fill the cache of the lxc download template with the debian release of the
# node, sourced by debian.sh: the container of the qa test 015 runs the
# release of the node, from this cache (--force-cache), and installs the
# agent from the debs of the lab.
#
# The cached rootfs holds the dependencies of the opensvc-server and
# opensvc-client debs that the images of images.linuxcontainers.org lack, so
# that the install of the agent in the container downloads nothing.
# A failure fails the build: a node without the cache would download the
# rootfs and the dependencies at test time.

which lxc-create >/dev/null 2>&1 || {
    echo "no lxc-create: no lxc cache"
    return 0
}

# The dependencies apt adds to the opensvc debs in the container of test
# 015, their libraries pulled in (libnftables, libnftnl, libjansson,
# libsgutils2).
LXC_DEBIAN_DEPS="nftables sg3-utils bash-completion"
LXC_DEBIAN_CT=lxc-cache-debian
LXC_DEBIAN_CACHE=/var/cache/lxc/download/debian/$VERSION_CODENAME/amd64/default
LXC_DEBIAN_ROOTFS=/var/lib/lxc/$LXC_DEBIAN_CT/rootfs

echo "Loading LXC cache, debian $VERSION_CODENAME, with $LXC_DEBIAN_DEPS"
lxc-create -n $LXC_DEBIAN_CT -t download -- --dist debian --release $VERSION_CODENAME --arch amd64 || {
    echo "lxc download template failed for debian $VERSION_CODENAME" >&2
    exit 1
}

# apt runs in a chroot of the rootfs: the resolver of the build vm, and no
# service started by the postinst scripts.
mv $LXC_DEBIAN_ROOTFS/etc/resolv.conf $LXC_DEBIAN_ROOTFS/etc/resolv.conf.lxc-cache 2>/dev/null
cp -L /etc/resolv.conf $LXC_DEBIAN_ROOTFS/etc/resolv.conf
printf '#!/bin/sh\nexit 101\n' > $LXC_DEBIAN_ROOTFS/usr/sbin/policy-rc.d
chmod 755 $LXC_DEBIAN_ROOTFS/usr/sbin/policy-rc.d
chroot $LXC_DEBIAN_ROOTFS sh -c "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $LXC_DEBIAN_DEPS && apt-get clean"
rc=$?
rm -f $LXC_DEBIAN_ROOTFS/usr/sbin/policy-rc.d $LXC_DEBIAN_ROOTFS/etc/resolv.conf
mv $LXC_DEBIAN_ROOTFS/etc/resolv.conf.lxc-cache $LXC_DEBIAN_ROOTFS/etc/resolv.conf 2>/dev/null
if [ $rc -ne 0 ]; then
    echo "install of $LXC_DEBIAN_DEPS in the debian $VERSION_CODENAME rootfs failed" >&2
    exit 1
fi

# The download template wrote the name of the container in place of the
# LXC_NAME placeholder of the files the cache lists in templates (hostname,
# hosts): put it back, for the containers made from the cache to get their
# own name.
while read -r f; do
    [ -f "$LXC_DEBIAN_ROOTFS$f" ] && sed -i "s/\b$LXC_DEBIAN_CT\b/LXC_NAME/g" "$LXC_DEBIAN_ROOTFS$f"
done < $LXC_DEBIAN_CACHE/templates
if grep -rlI "$LXC_DEBIAN_CT" $LXC_DEBIAN_ROOTFS/etc; then
    echo "the debian $VERSION_CODENAME rootfs still names $LXC_DEBIAN_CT" >&2
    exit 1
fi

# The rootfs with the dependencies replaces the one of the cache, in the
# format the download template extracts (tar --numeric-owner -xpJf).
tar --numeric-owner -C $LXC_DEBIAN_ROOTFS -cpJf $LXC_DEBIAN_CACHE/rootfs.tar.xz.new . && \
    mv -f $LXC_DEBIAN_CACHE/rootfs.tar.xz.new $LXC_DEBIAN_CACHE/rootfs.tar.xz || {
    echo "repack of the debian $VERSION_CODENAME lxc cache failed" >&2
    exit 1
}
lxc-destroy -n $LXC_DEBIAN_CT
ls -l $LXC_DEBIAN_CACHE
du -sh /var/cache/lxc/
