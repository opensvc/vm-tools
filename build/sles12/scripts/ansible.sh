#!/bin/bash -eu

echo "--- Begin ansible.sh ---"

zypper --non-interactive --gpg-auto-import-keys python-pip

pip install ansible==2.9.2

# ansible.posix >= 2.2.1 calls os.chown(follow_symlinks=), python3 only
ansible-galaxy collection install ansible.posix:1.5.4 --server="https://old-galaxy.ansible.com"

echo "--- End ansible.sh ---"
