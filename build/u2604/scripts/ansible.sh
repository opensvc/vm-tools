#!/bin/bash -eu

echo "--- Begin ansible.sh ---"

export DEBIAN_FRONTEND=noninteractive

# Install Ansible repository.
apt -y update && sudo apt-get -y dist-upgrade
apt -y install software-properties-common

# Install Ansible.
apt -y install ansible

echo "--- End ansible.sh ---"
