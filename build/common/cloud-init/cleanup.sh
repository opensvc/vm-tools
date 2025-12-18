#!/bin/bash

echo
echo "#########################"
echo "######## CLEANUP ########"
echo "#########################"
echo

[[ -f ~opensvc/opensvc-qa.sh ]] && . ~opensvc/opensvc-qa.sh

#grep -q ^packer /etc/passwd && {
#    echo "Deleting user packer"
#    userdel -r packer 2>/dev/null
#}

grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config || {
    echo "Disabling ssh password auth"
    echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
}

test -x /nfs/data/tools/set_passwords.sh && {
    echo "Set passwords"
    /nfs/data/tools/set_passwords.sh
}

exit 0
