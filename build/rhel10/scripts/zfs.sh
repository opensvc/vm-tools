#!/bin/bash
#

echo "ZFS Build"

#RHEL 10
echo "Installing RHEL build packages dependencies"
dnf -y install gcc make autoconf automake libtool rpm-build libtirpc-devel libblkid-devel libuuid-devel libudev-devel openssl-devel zlib-devel libaio-devel libattr-devel  python3 python3-devel python3-setuptools python3-cffi libffi-devel git libcurl-devel kernel-devel

echo "Git cloning ZFS repository"
git clone https://github.com/openzfs/zfs

echo "Building ZFS"
cd ./zfs
git checkout zfs-2.4.0

sh autogen.sh

cat META

# dirty hack
sed -i 's/CDDL/APL/' META

cat META

CFG_OPTS=""
#grep -q '12-' /etc/os-release && CFG_OPTS="$CFG_OPTS --with-python=3.6"

./configure $CFG_OPTS
make -j$(nproc) || exit 1

make install || exit 1

for cmd in zfs zpool fsck.zfs zdb zed zfs_ids_to_path zgenhostid zhack zinject zstream ztest zstreamdump
do
ln -s /usr/local/sbin/$cmd /usr/sbin/$cmd
ln -s /usr/local/sbin/$cmd /sbin/$cmd
done


#cat - <<EOF > /etc/modprobe.d/10-unsupported-modules.conf
#allow_unsupported_modules 1
#EOF

cat - <<EOF > /etc/modules-load.d/10-load-opensvc-modules.conf
zfs
drbd
EOF


# cleanup
cd .. && rm -rf zfs

modinfo zfs | grep ^version || exit 1

exit 0
