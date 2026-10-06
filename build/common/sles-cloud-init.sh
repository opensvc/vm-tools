#!/bin/bash

echo "Installing Cloud Init"

zypper --non-interactive --gpg-auto-import-keys install cloud-init
systemctl enable cloud-init.service
systemctl enable cloud-init-local.service
systemctl enable cloud-config.service
systemctl enable cloud-final.service

# The NoCloud seed cdrom can show up after the initrd switched root, too
# late for ds-identify, which then disables cloud-init for that boot.
# With a single datasource, ds-identify enables cloud-init without probing
# devices and NoCloud reads the seed later, from cloud-init-local.
cat > /etc/cloud/cloud.cfg.d/91-datasource-nocloud.cfg <<CFG
datasource_list: [ NoCloud ]
CFG
