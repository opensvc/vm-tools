#!/bin/bash -eu

echo "--- Begin ansible.sh ---"

yum -y --disablerepo="*" --enablerepo=rhel-7-server-ansible-2-rpms install ansible

# ansible.posix >= 2.2.1 calls os.chown(follow_symlinks=), python3 only
ansible-galaxy collection install ansible.posix:1.5.4

echo "--- End ansible.sh ---"
