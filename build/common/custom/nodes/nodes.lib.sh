#/bin/bash

function gen_etc_hosts()
{
node=$1
ipprd=$2
iphb1=$3
iphb2=$4

cat > /etc/hosts <<-ENDOFMESSAGE
#
# Copyright 2009 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#
# Internet host table
#
::1 localhost 
127.0.0.1 localhost loghost 
$ipprd $node
$iphb1 $node-hb1
$iphb2 $node-hb2

ENDOFMESSAGE

}

function createnic()
{
    NIC=$1
    SUBNETPREFIX=$2
    CLUSTERID=$3
    NETWORK=$4
    IP=$5
    echo
    echo "#######################################"
    echo "## createnic $NIC $SUBNETPREFIX $NETWORK $IP ##"
    netstate=$(ipadm show-if -o state $NIC 2>/dev/null | grep -v ^STATE)
    ret=$?
    [[ $ret -ne 0 && $netstate != "ok" ]] && {
        echo "Configuring $NIC interface on ${SUBNETPREFIX}.${CLUSTERID}.${NETWORK}.${IP}"
        ipadm create-ip $NIC
        ipadm create-addr -T static -a ${SUBNETPREFIX}.${CLUSTERID}.${NETWORK}.${IP}/24 $NIC/opensvc
    }
    [[ $ret -eq 0 ]] && {
        echo
        echo "Before config change"
        echo "--------------------"
        ipadm show-addr $NIC
        echo
        echo "Updating $NIC interface config with ${SUBNETPREFIX}.${CLUSTERID}.${NETWORK}.${IP}"
        ipadm show-addr $NIC -p -o addrobj | xargs -n1 ipadm delete-addr
        ipadm create-addr -T static -a ${SUBNETPREFIX}.${CLUSTERID}.${NETWORK}.${IP}/24 $NIC/opensvc
        echo; echo
        echo "After config change"
        echo "-------------------"
        ipadm show-addr $NIC
        echo
    }
    grep -q "^${SUBNETPREFIX}.${CLUSTERID}.${NETWORK}.0" /etc/netmasks || {
            echo "${SUBNETPREFIX}.${CLUSTERIDcluid}.${NETWORK}.0     255.255.255.0" >> /etc/netmasks
    }
    echo
    echo "## End of createnic $NIC $NETWORK $IP ##"
    echo "################################"
    echo
}

function create_bridge()
{
    local BRIDGE=$1
    local LINKS=$2
    local link
    echo "#########################"
    echo "## create_bridge '$BRIDGE' with links: '$LINKS'"
    if ! dladm show-bridge -l $BRIDGE >/dev/null 2>&1 ; then
        echo "## create bridge: dladm create-bridge $BRIDGE"
        dladm create-bridge $BRIDGE || return 1
    else
        echo already created
    fi
    for link in $LINKS
    do
        echo "## ensure link $link present on bridge $BRIDGE"
        dladm show-bridge -l -p -o link $BRIDGE | egrep "^$link$" > /dev/null && echo already ok && continue        
        echo "## add link: dladm add-bridge -l $link $BRIDGE"
        dladm add-bridge -l $link $BRIDGE || return 1
    done
    echo
    echo "## summary"
    echo "## show bridge: dladm show-bridge $BRIDGE"
    dladm show-bridge $BRIDGE
    echo "## show bridge links: dladm show-bridge -l $BRIDGE"
    dladm show-bridge -l $BRIDGE
    echo "## show link bridge: dladm show-link ${BRIDGE}0"
    dladm show-link ${BRIDGE}0
    echo "## End of create_bridge '$BRIDGE' with links: '$LINKS'"
    echo "#########################"
}

function update_svccfg()
{
    # ensure svccfg config is correct
    # it updates NEED_REFRESH var with smf name if refresh is needed
    local smf=$1
    local prop=$2
    local value_type=$3
    local value=$4
    local multi=$5
    if ! svccfg -s $smf  listprop -o value $prop | egrep "^$value$" > /dev/null; then
        svccfg -s $smf listprop $prop
        if [ -n "$multi" ] ; then
            echo "## update smf $smf: svccfg -s $smf setprop $prop  = $value_type: ($value)"
            svccfg -s $smf setprop $prop  = $value_type: \($value\) || return 1
        else
            echo "## update smf $smf: svccfg -s $smf setprop $prop  = $value_type: $value"
            svccfg -s $smf setprop $prop  = $value_type: "$value" || return 1
        fi
        echo " $NEED_REFRESH " | egrep " $smf " >/dev/null || NEED_REFRESH="$NEED_REFRESH $smf"
    fi
}

function setup_dns_client()
{
    local nameservers=$1
    local searches=$2
    echo "#########################"
    echo "## setup_dns_client nameservers: '$nameservers' searches: '$searches'"
    NEED_REFRESH=""
    update_svccfg network/dns/client:default config/nameserver net_address "$nameservers" multi || return 1
    update_svccfg network/dns/client:default config/search astring "$searches" multi || return 1
    update_svccfg name-service/switch config/host astring '"files dns"' || return 1
    if [ -n "$NEED_REFRESH" ]; then
            echo "## svcadm refresh -s $NEED_REFRESH"
            svcadm refresh -s $NEED_REFRESH

	    echo "## svcadm disable $NEED_REFRESH ; svcadm enable $NEED_REFRESH"
	    svcadm disable -s $NEED_REFRESH
	    svcadm enable -r -s $NEED_REFRESH
    fi
    echo
    echo "## summary"
    echo "## show resolv.conf"
    egrep -v '^$|^#' /etc/resolv.conf
    echo "## extract of /etc/nsswitch.conf"
    egrep "host|node" /etc/nsswitch.conf
    echo "## end of setup_dns_client nameservers: '$nameservers' searches: '$searches'"
    echo "#########################"
}

function setup_ssh()
{
    gsed -i -e "s/^PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config 
    gsed -i -e "s/^GSSAPIAuthentication yes/GSSAPIAuthentication no/" /etc/ssh/sshd_config 
    gsed -i -e "s/^PermitRootLogin no/PermitRootLogin yes/" /etc/ssh/sshd_config 
}

function setup_root_role()
{
    if getent user_attr root | egrep "type=role" ; then
        echo "changing root to type normal"
        rolemod -K type=normal root
        getent user_attr root
    fi
}

function setup_sudo_secure_path()
{
grep -q "^Defaults secure_path=" /etc/sudoers || {
    echo "Set default sudo secure_path"
    /usr/gnu/bin/sed -i 's@# Defaults secure_path=.*@Defaults secure_path="/opt/csw/bin:/usr/gnu/bin:/usr/xpg4/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"@' /etc/sudoers
    }
}

function setup_opensvc_user_path()
{
grep -q 'opt/csw/bin:/usr/gnu/bin:/usr/xpg4/bin' /export/home/opensvc/.profile || {
    echo "Setup vagrant user PATH"
    echo 'export PATH="/opt/csw/bin:/usr/gnu/bin:/usr/xpg4/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' | tee -a /export/home/opensvc/.profile
    }
}

function setup_timezone()
{
    svccfg -s timezone:default setprop timezone/localtime=Europe/Paris
    svcadm refresh timezone:default
}

function setup_iscsi()
{
    local NODE=$1
    local CLUSTERID=$2

    ISCSITGTIP=$(getent hosts c${CLUSTERID}nas|awk '{print $1}')
    echo "NAS IP: $ISCSITGPIP"
    
    # iscsi alias
    ALIASSE=$(iscsiadm list initiator-node|egrep 'Initiator node alias'|awk '{print $4}')
    if [[ "$ALIASSE" == "$NODE" ]]; then
        echo "ALIAS is already set to $NODE"
    else
        echo "set ALIAS to $NODE"
        iscsiadm modify initiator-node -A $NODE
        sleep 1
    fi
    
    # iscsi iqn
    IQN=$(iscsiadm list initiator-node|egrep 'Initiator node name'|awk '{print $4}')
    if [[ "$IQN" == "iqn.2009-11.com.opensvc.srv:$NODE.storage.initiator" ]]; then
        echo "IQN is already set to iqn.2009-11.com.opensvc.srv:$NODE.storage.initiator"
    else
        echo "set IQN to iqn.2009-11.com.opensvc.srv:$NODE.storage.initiator"
        iscsiadm modify initiator-node -N "iqn.2009-11.com.opensvc.srv:$NODE.storage.initiator"
        sleep 1
    fi
    
    DISCO=$(iscsiadm list discovery-address|egrep 'Discovery Address'|awk '{print $3}')
    if [[ "$DISCO" == "$ISCSITGTIP:3260" ]]; then
        echo "DISCOVERY is already set to $ISCSITGTIP:3260"
    else
        echo "set DISCOVERY to $ISCSITGTIP:3260"
        iscsiadm add discovery-address $ISCSITGTIP:3260
        sleep 1
        iscsiadm modify discovery --sendtargets enable
        sleep 1
        devfsadm -i iscsi
    fi
}

function setup_autofs()
{
    local NFSSRV=$1

grep -q osvcdata /etc/auto_master || {
cat - <<EOF >>/etc/auto_master
/nfs    auto_osvcdata
EOF
}

[[ ! -f /etc/auto_osvcdata ]] && {
cat - <<EOF >|/etc/auto_osvcdata
data ${NFSSRV}:/data/nfsshare
EOF
}

    svcadm restart -s autofs
}

function set_hostid()
{
    HIDBEFORE=$(hostid)
    PADSTR=$(seq -f "3%g" 0 8 | shuf -n 10 | awk '{printf "%s ", $1} END {printf "0\n"}')
    echo "hw_serial/v $PADSTR" | mdb -kw >> /dev/null
    HIDAFTER=$(hostid)
    echo "hostid is now $HIDAFTER [was $HIDBEFORE]"
}

function auto_clear_smf()
{
    echo "Install custom opensvc-clear-smf to clear /lib/svc/method/fs-local transiant failure during boot"
    echo "Because /export/home/opensvc may be busy"

    SMF_CLEAR_CMD='/root/opensvc-clear-smf.sh'
    DELAY=5
    PERIOD=30
    JITTER=5

    cat > $SMF_CLEAR_CMD <<'EOF'
#!/bin/ksh -p

AUTO_CLEAR_SVCS="svc:/system/filesystem/local:default"

for svc in $AUTO_CLEAR_SVCS
do
        [ "$(svcs -H -o state $svc)" != maintenance ] && continue
        echo "service $svc is in maintenance, try svcadm clear $svc"
        svcadm clear $svc
        echo "sleep 2"
        sleep 2
        echo "svcs -p $svc"
        svcs -p $svc
done

EOF

    chmod +x $SMF_CLEAR_CMD

    cat > /tmp/opensvc-clear-smf.xml <<EOF
<?xml version='1.0'?>
<!DOCTYPE service_bundle SYSTEM '/usr/share/lib/xml/dtd/service_bundle.dtd.1'>
<service_bundle type='manifest' name='export'>
    <service name='opensvc/clear-smf' type='service' version='0'>
        <create_default_instance enabled='true' complete='true'/>
        <single_instance/>
        <dependency name='single-user' grouping='require_all' restart_on='none' type='service'>
            <service_fmri value='svc:/milestone/single-user'/>
        </dependency>
        <periodic_method period='$PERIOD' delay='$DELAY' jitter='$JITTER' exec='$SMF_CLEAR_CMD' timeout_seconds='0'>
            <method_context>
                <method_credential user='root' group='root'/>
            </method_context>
        </periodic_method>
        <stability value='Unstable'/>
        <template>
            <common_name>
                <loctext xml:lang='C'>automatic clear smf failures</loctext>
            </common_name>
        </template>
    </service>
</service_bundle>
EOF

    svccfg import /tmp/opensvc-clear-smf.xml
}
