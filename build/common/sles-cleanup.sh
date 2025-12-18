#!/bin/bash -eux

echo "--- Begin Suse cleanup.sh ---"

echo "cloud-init"
cloud-init clean

echo "Cleanup old kernels (avoid dracut err 107 complaining against missing zfs.ko for all kernel versions except this one)"
CURRENT_VER=$(uname -r| sed -e 's/-default//')
rpm -qa | grep -E "kernel-default|kernel-source" | grep -v ${CURRENT_VER} | xargs sudo zypper --non-interactive remove

echo "delete the massive firmware files"
rm -rf /lib/firmware/*
rm -rf /usr/share/doc/linux-firmware/*

echo "remove /usr/share/doc/"
rm -rf /usr/share/doc/*

echo "remove /var/cache"
find /var/cache -type f -exec rm -rf {} \;

echo "truncate any logs that have built up during the install"
find /var/log -type f -exec truncate --size=0 {} \;

echo "blank netplan machine-id (DUID) so machines get unique ID generated on boot"
truncate -s 0 /etc/machine-id
if test -f /var/lib/dbus/machine-id
then
  truncate -s 0 /var/lib/dbus/machine-id  # if not symlinked to "/etc/machine-id"
fi

echo "remove the contents of /tmp and /var/tmp"
rm -rf /tmp/* /var/tmp/*

echo "remove the contents of /opt/archives"
rm -rf /opt/archives

echo "force a new random seed to be generated"
rm -f /var/lib/systemd/random-seed

echo "clear the history so our install isn't there"
rm -f /root/.wget-hsts
export HISTSIZE=0

echo "removing udev persistent naming rules"
rm -f /etc/udev/rules.d/*

echo "removing network configurations"
for file in ifcfg-br0 ifcfg-eth0
do
	if test -f /etc/sysconfig/network/$file
	then
		rm -f /etc/sysconfig/network/$file
	fi
done

echo "Remove ssh host keys"
rm -f /etc/ssh/ssh_host_*

dd if=/dev/zero of=/EMPTY bs=1M || /bin/true
rm -f /EMPTY

echo "Locking user: packer"
sudo passwd -l packer

sync; sync

echo "--- End cleanup.sh ---"
