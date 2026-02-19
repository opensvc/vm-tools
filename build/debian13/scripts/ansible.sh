#!/bin/bash -eu

echo "--- Begin ansible.sh ---"

export DEBIAN_FRONTEND=noninteractive

sudo apt update && sudo apt -y install ansible

apt clean

echo "--- End ansible.sh ---"
