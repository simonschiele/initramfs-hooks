#!/bin/sh

#
# configurable network initramfs hook 
# by simon <simon.codingmonkey@googlemail.com>
#

##### Config {{{ ###################

# useraccount that will be copied to initramfs, additional to the root account
username=simon

# setup network (if dhcp=true you can ignore ip_adress, netmask and gateway.
# nameserver and extended routing are optional anyways.)
interface=eth0
dhcp=true
ip_address="192.168.5.200"
netmask="255.255.255.0"
gateway="192.168.5.1"
nameserver=""  
extended_routing="" # normally not needed, leave blank

# These are my settings for a hetzner rootserver
#ip_address="178.63.94.74"
#netmask="255.255.255.192"
#gateway="178.63.94.65"
#extended_routing="route add -net 178.63.94.64 netmask 255.255.255.192 gw 178.63.94.65"

# Hostname for greeting line
hostname="cpad.cnet"

# openvpn support (needs also openvpn.sh hook)
openvpn=false

depends="/bin/loadkeys /bin/chvt /usr/sbin/dropbear /usr/bin/passwd /bin/login"
needed_directories="/usr/sbin/ /root/.ssh/ /var/run/ /var/tmp/ /var/lock /var/log /etc/dropbear /lib/i386-linux-gnu /lib/x86_64-linux-gnu"

######## }}} #######################

PREREQ=""

prereqs()
{
    echo "$PREREQ"
}

error_exit()
{
    echo "[ERROR] $1"
    exit 1
}

warning()
{
    echo "[WARNING] $1"
}

case $1 in
    prereqs)
        prereqs
        exit 0
    ;;
esac

. /usr/share/initramfs-tools/hook-functions
echo "> Including network.sh into initramfs"

if ( $debug )
then
    depends="$depends /usr/bin/strace /bin/nc"
fi

if ( $dhcp )
then
    echo "Will use dhcp for network config."
    depends="$depends /sbin/dhclient"
else
    echo "Will use static network config ($ip_address - $netmask)."
    if [ -z $netmask ] || [ -z $ip_address ]
    then
        error_exit "Please set ip address and netmask if you don't use dhcp"
    fi
fi

if ! [ -e /etc/dropbear/log/main ]
then
    touch /etc/dropbear/log/main 
fi

for dir in $needed_directories
do
    mkdir -p ${DESTDIR}${dir}
done
chmod 777 ${DESTDIR}/var/tmp/ -R

for dep in $depends
do
    if [ ! -x $dep ]
    then
        error_exit "Missing Depends: $dep"
    fi
    copy_exec $dep
done

echo -e "/bin/sh\n/bin/bash\n" > ${DESTDIR}/etc/shells
grep -e root -e $username /etc/shadow > ${DESTDIR}/etc/shadow
grep -e root -e $username /etc/passwd | sed -e 's@/bin/\(false\|bash\|sh\|zsh\|screen\)@/bin/sh@g' -e "s|/home/.*:|/home/${username}:|g" > ${DESTDIR}/etc/passwd
mkdir -p ${DESTDIR}/home/$username
chown $username: ${DESTDIR}/home/$username -R

##### Generate Scripts {{{ #########

# startscript for dropbear ssh daemon 
cat >${DESTDIR}/scripts/local-top/sshd << 'EOF'
#!/bin/sh

PREREQ="network"

prereqs()
{
    echo "$PREREQ"
}

case $1 in
    prereqs)
        prereqs
        exit 0
    ;;
esac

sleep 1
touch /var/log/lastlog

echo "Starting dropbear ssh daemon."
/usr/sbin/dropbear -E -b /etc/dropbear/banner -d /etc/dropbear/dropbear_dss_host_key -r /etc/dropbear/dropbear_rsa_host_key -p22 >/dev/null 2>&1 &

EOF
if ( $openvpn )
then
    sed -i 's|PREREQ="network"|PREREQ="openvpn"|g' ${DESTDIR}/scripts/local-top/sshd
fi
chmod 700 ${DESTDIR}/scripts/local-top/sshd


# Setup script for setting up the network
cat >${DESTDIR}/scripts/local-top/network << 'EOF'
#!/bin/sh

PREREQ="udev"

mode="MODE"
interface="INTERFACE"
ip_address="IP_ADDRESS"
netmask="NETMASK"
gateway="GATEWAY"

prereqs()
{
    echo "$PREREQ"
}

case $1 in
    prereqs)
        prereqs
        exit 0
    ;;
esac

echo "Configuring the Network."

if ( cat /proc/cmdline | grep -i -q "nethook_mode=" )
then
    cmd_mode=$( cat /proc/cmdline | sed "s|.*nethook_mode=\(.*\).*|\1|g" | cut -f1 -d' ' )
    if [ -n "$cmd_mode" ]
    then
        #echo "> Overwriting mode to kernel paramter value: '$cmd_mode'"
        mode="$cmd_mode"
    fi
fi

if ( cat /proc/cmdline | grep -i -q "nethook_interface=" )
then
    cmd_interface=$( cat /proc/cmdline | sed "s|.*nethook_interface=\(.*\).*|\1|g" | cut -f1 -d' ' )
    if [ -n "$cmd_interface" ]
    then
        #echo "> Overwriting interface to kernel paramter value: '$cmd_interface'"
        interface="$cmd_interface"
    fi
fi

ifconfig $interface up
if [ "$mode" == "static" ]
then
    echo "> Using static configuration ($ip_address / $netmask)"
    ifconfig $interface $ip_address netmask $netmask >/dev/null 2>&1
    route add default $interface >/dev/null 2>&1
    route add default gw $gateway >/dev/null 2>&1
else
    echo "> Using DHCP."
    udhcpc -p /tmp/bb_udhcpc.pid -f -i $interface -s /bin/simple.script >/dev/null 2>&1 &
fi

EOF
sed -i "s|INTERFACE|$interface|g" ${DESTDIR}/scripts/local-top/network
sed -i "s|IP_ADDRESS|$ip_address|g" ${DESTDIR}/scripts/local-top/network
sed -i "s|NETMASK|$netmask|g" ${DESTDIR}/scripts/local-top/network
sed -i "s|GATEWAY|$gateway|g" ${DESTDIR}/scripts/local-top/network
if ( $dhcp )
then
    sed -i 's|MODE|dhcp|g' ${DESTDIR}/scripts/local-top/network
else
    sed -i 's|MODE|static|g' ${DESTDIR}/scripts/local-top/network
fi

if [ -n "$extended_routing" ]
then
    echo "${extended_routing}" >> ${DESTDIR}/scripts/local-top/network
fi

if [ -n "$nameserver" ]
then
    echo "echo \"nameserver ${nameserver}\" > /etc/resolv.conf" >> ${DESTDIR}/scripts/local-top/network
fi
chmod 700 ${DESTDIR}/scripts/local-top/network

# Banner for dropbear
cat >${DESTDIR}/etc/dropbear/banner << 'EOF'

    Initramfs on HOSTNAME 
      
EOF
sed -i "s|HOSTNAME|$hostname|g" ${DESTDIR}/etc/dropbear/banner

# dhcp setup - This script is from busybox project
# (http://git.busybox.net/busybox/plain/examples/udhcp/simple.script)
cat >${DESTDIR}/bin/simple.script << 'EOF'
#!/bin/sh
# udhcpc script edited by Tim Riker <Tim@Rikers.org>

RESOLV_CONF="/etc/resolv.conf"

[ -n "$1" ] || { echo "Error: should be called from udhcpc"; exit 1; }

NETMASK=""
[ -n "$subnet" ] && NETMASK="netmask $subnet"
BROADCAST="broadcast +"
[ -n "$broadcast" ] && BROADCAST="broadcast $broadcast"

case "$1" in
    deconfig)
        #echo "Setting IP address 0.0.0.0 on $interface"
        ifconfig $interface 0.0.0.0 >/dev/null 2>&1
        ;;

    renew|bound)
        #echo "Setting IP address $ip on $interface"
        ifconfig $interface $ip $NETMASK $BROADCAST >/dev/null 2>&1

        if [ -n "$router" ] ; then
            #echo "Deleting routers"
            while route del default gw 0.0.0.0 dev $interface >/dev/null 2>&1 ; do
                :
            done

            metric=0
            for i in $router ; do
                #echo "Adding router $i"
                route add default gw $i dev $interface metric $((metric++)) >/dev/null 2>&1
            done
        fi

        #echo "Recreating $RESOLV_CONF"
        echo -n > $RESOLV_CONF-$$
        [ -n "$domain" ] && echo "search $domain" >> $RESOLV_CONF-$$
        for i in $dns ; do
            #echo " Adding DNS server $i"
            echo "nameserver $i" >> $RESOLV_CONF-$$
        done
        mv $RESOLV_CONF-$$ $RESOLV_CONF >/dev/null 2>&1
        ;;
esac

exit 0 
EOF
chmod 700 ${DESTDIR}/bin/simple.script 

######## }}} #######################

##### copy depends {{{ #########

if [ ! -e /etc/dropbear/dropbear_dss_host_key ] || [ ! -e /etc/dropbear/dropbear_rsa_host_key ]
then
    error_exit "Dropbear keys not found"
else
    cp -frpL /etc/dropbear ${DESTDIR}/etc/
fi

cp -fpL /etc/nsswitch.conf ${DESTDIR}/etc/
cp -fpL /etc/localtime ${DESTDIR}/etc/
cp -fpL /etc/group ${DESTDIR}/etc/
cp -fpL /etc/gai.conf ${DESTDIR}/etc/
cp -fpL /etc/ld.so.cache ${DESTDIR}/etc/

if ( uname -m | grep -q "i[0-9]86" )
then
    cp -fprL /lib/libns* ${DESTDIR}/lib/ 
    cp -fpL /lib/i386-linux-gnu/libns* ${DESTDIR}/lib/i386-linux-gnu/
elif ( uname -m | grep -q "x86.*64" ) 
then
    cp -fpL /lib/x86_64-linux-gnu/libns* ${DESTDIR}/lib/x86_64-linux-gnu/ 
else
    error_exit "your architecture ($( uname -m )) seems not to be supported."
fi

######## }}} #######################

echo "> Including network.sh into initramfs - SUCCESSFUL"
exit 0

