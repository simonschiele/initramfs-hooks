#!/bin/sh

#
# initramfs hook for booting remote machines with luks encrypted root filesystem
# by simon <simon.codingmonkey@googlemail.com>
#

##### Config {{{ ###################

# needed directorys that will be created in initramfs
needed_directories="/usr/sbin/ /proc/ /root/.ssh/ /var/run/ /var/tmp/ /var/lock /var/log /etc/dropbear /lib/i386-linux-gnu"

# depends that are not installed automatically - optional depends are only used
# if installed on the base system.
depends="/sbin/cryptsetup /bin/loadkeys /bin/chvt /usr/sbin/dropbear /usr/bin/passwd /bin/login /sbin/dmsetup"
optional_depends="/sbin/mdadm"

# useraccount that will be copied to initramfs, additional to the root account
username=simon

# include debugging tools 
debug=true

# openvpn support - needs openvpn.sh hook enabled
openvpn=false

# setup network (if dhcp=true you can ignore ip_adress, netmask and gateway.
# nameserver and extended routing are optional anyways.)
dhcp=true
interface=eth0
ip_address="178.63.94.74"
netmask="255.255.255.192"
gateway="178.63.94.65"
nameserver=""
extended_routing="route add -net 178.63.94.64 netmask 255.255.255.192 gw 178.63.94.65" # normally not needed, leave blank

# Hostname for greeting line
hostname="nerdmail.de"

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
echo "> Including cryptoroot.sh into initramfs"

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

for dep in $optional_depends
do
    if [ ! -x $dep ]
    then
        warning "Missing Depends: $dep"
    else
        copy_exec $dep
    fi
done

echo -e "/bin/sh\n/scripts/local-top/cryptroot_block" > ${DESTDIR}/etc/shells
grep -e root -e $username /etc/shadow > ${DESTDIR}/etc/shadow
grep -e root -e $username /etc/passwd | sed -e 's@/bin/\(false\|bash\|sh\|zsh\|screen\)@/scripts/local-top/cryptroot_block@g' -e 's|/home/.*:|/var/tmp:|g' > ${DESTDIR}/etc/passwd

##### Generate Scripts {{{ #########

# Menu / Blocker Script
cat >${DESTDIR}/scripts/local-top/cryptroot_block << 'EOF'
#!/bin/sh

PREREQ="ssh"

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

menu()
{
    Command
}

message() 
{
    echo ''
    echo ''
    echo 'Welcome to @hostname@'
    echo ''
    echo ''
    echo 'Available commands:'
    echo ' unlock)   Decrypt and mount Harddisks'
    echo ' sh)       Start sh'
    echo ' reboot)   Rebooting the System'
    echo ' boot)     Continue booting'
    echo ''
    echo ''
    echo 'Please input Command:'
}

clear
message

INPUT='wait'
while ( true )
do
    echo -n ' > '
    read INPUT
    
    if [ -z $INPUT ] 
    then
        echo ''
    elif [ $INPUT == 'sh' ] || [ $INPUT == 'shell' ]
    then
        /bin/sh
        clear
        message
    elif [ $INPUT == 'unlock' ]
    then
        clear
        /bin/decrypt 
        clear
        message
    elif [ $INPUT == 'reboot' ] || [ $INPUT == 'restart' ]
    then
        echo "Rebooting the System"
        reboot
    elif [ $INPUT == 'boot' ] || [ $INPUT == 'continue' ]
    then
        clear
        echo "Continue booting..."
        break
    else
        echo "ERROR: unknown command $INPUT"
    fi
done

killall -9 cryptroot_block 1>&2 2>/dev/null

EOF
sed -i "s|@hostname@|$hostname|g" ${DESTDIR}/scripts/local-top/cryptroot_block 
chmod 700 ${DESTDIR}/scripts/local-top/cryptroot_block

# startscript for dropbear ssh daemon 
cat >${DESTDIR}/scripts/local-top/ssh << 'EOF'
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
/usr/sbin/dropbear -E -b /etc/dropbear/banner -d /etc/dropbear/dropbear_dss_host_key -r /etc/dropbear/dropbear_rsa_host_key -p22 &

EOF
if ( $openvpn )
then
    sed -i 's|PREREQ="network"|PREREQ="openvpn"|g' ${DESTDIR}/scripts/local-top/ssh
fi
chmod 700 ${DESTDIR}/scripts/local-top/ssh

# Setup script for setting up the network
cat >${DESTDIR}/scripts/local-top/network << 'EOF'
#!/bin/sh

PREREQ="udev"

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
@netconfig@

EOF

netconfig="ifconfig $interface up\n"
if ( $dhcp )
then
    netconfig="${netconifg}udhcpc -b -s /bin/simple.script -i $interface\n"
else
    netconfig="${netconfig}ifconfig $interface $ip_address netmask $netmask\n"
    netconfig="${netconfig}route add default $interface\n"
    netconfig="${netconfig}route add default gw $gateway\n"
    
    if [ -n "$extended_routing" ]
    then
        netconfig="${netconfig}${extended_routing}\n"
    fi

fi

if [ -n "$nameserver" ]
then
    netconfig="${netconfig}echo namerserver $nameserver > /etc/resolv.conf\n"
fi

sed -i "s|@netconfig@|$netconfig|g" ${DESTDIR}/scripts/local-top/network
chmod 700 ${DESTDIR}/scripts/local-top/network

# Cleanup script for dropbear 
cat >${DESTDIR}/scripts/local-bottom/kill_dropbear << 'EOF'
#!/bin/sh

PREREQ=""

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

echo "Killing all running dropbear daemons."
killall -9 dropbear 1>&2 2>/dev/null

EOF
chmod 700 ${DESTDIR}/scripts/local-bottom/kill_dropbear

# Banner for dropbear
cat >${DESTDIR}/etc/dropbear/banner << 'EOF'

    Initramfs on @hostname@ 
      
EOF
sed -i "s|@hostname@|$hostname|g" ${DESTDIR}/etc/dropbear/banner

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
        echo "Setting IP address 0.0.0.0 on $interface"
        ifconfig $interface 0.0.0.0
        ;;

    renew|bound)
        echo "Setting IP address $ip on $interface"
        ifconfig $interface $ip $NETMASK $BROADCAST

        if [ -n "$router" ] ; then
            echo "Deleting routers"
            while route del default gw 0.0.0.0 dev $interface ; do
                :
            done

            metric=0
            for i in $router ; do
                echo "Adding router $i"
                route add default gw $i dev $interface metric $((metric++))
            done
        fi

        echo "Recreating $RESOLV_CONF"
        echo -n > $RESOLV_CONF-$$
        [ -n "$domain" ] && echo "search $domain" >> $RESOLV_CONF-$$
        for i in $dns ; do
            echo " Adding DNS server $i"
            echo "nameserver $i" >> $RESOLV_CONF-$$
        done
        mv $RESOLV_CONF-$$ $RESOLV_CONF
        ;;
esac

exit 0 
EOF
chmod 700 ${DESTDIR}/bin/simple.script 

# Little script to decrypt devices from crypttab 
cat >${DESTDIR}/bin/decrypt << 'EOF'
#!/bin/sh
# script to decrypt devices from crypttab (simon.codingmonkey@googlemail.com) 

if [ ! -e /etc/crypttab ]
then
    echo "Error: Could not find /etc/crypttab"
    exit 1
fi

echo "Decrypting devices from crypttab"

sed '/^$/d' /etc/crypttab | grep -v "/dev/urandom" | while read cryptline
do
    cryptname=$( echo "$cryptline" | awk {'print $1'} )
    cryptdevice=$( echo "$cryptline" | awk {'print $2'} )
    cryptsource=$( echo "$cryptline" | awk {'print $3'} )
    crypttype=$( echo "$cryptline" | awk {'print $4'} )
    
    if [ "$crypttype" != "luks" ]
    then
        echo "$cryptname ($cryptdevice) seems not to be a luks device - only luks is supported at the moment - will skip device"
    elif [ "$cryptsource" = "/dev/urandom" ]
    then
        echo "$cryptname ($cryptdevice) seems to be random swap - will skip device for now"
    else
        cryptdevice=$( echo "$cryptdevice" | sed 's|UUID=|/dev/disk/by-uuid/|g' )
        echo "Decrypting device $cryptdevice as $cryptname."
        while ( true )
        do
            if ( /sbin/cryptsetup luksOpen $cryptdevice $cryptname )
            then
                echo "$cryptname ($cryptdevice) unlocked."
                break
            else
                echo "Could not unlock $cryptname ($cryptdevice). Please try again."
            fi
        done
    fi
done

EOF
chmod 700 ${DESTDIR}/bin/decrypt


######## }}} #######################

##### copy depends {{{ #########

if [ -e /etc/mdadm/mdadm.conf ]
then
    mkdir -p ${DESTDIR}/etc/mdadm/
    cp -fpL /etc/mdadm/mdadm.conf ${DESTDIR}/etc/mdadm/
fi

if [ ! -e /etc/dropbear/dropbear_dss_host_key ] || [ ! -e /etc/dropbear/dropbear_rsa_host_key ]
then
    error_exit "Dropbear keys not found"
else
    cp -frpL /etc/dropbear ${DESTDIR}/etc/
fi

cp -fpL /etc/nsswitch.conf ${DESTDIR}/etc/
cp -fpL /etc/localtime ${DESTDIR}/etc/
cp -fpL /etc/fstab ${DESTDIR}/etc/
cp -fpL /etc/crypttab ${DESTDIR}/etc/
cp -fpL /etc/group ${DESTDIR}/etc/
cp -fpL /etc/gai.conf ${DESTDIR}/etc/
cp -fpL /etc/ld.so.cache ${DESTDIR}/etc/

cp -fprL /lib/libns* ${DESTDIR}/lib/ 
cp -fpL /lib/i386-linux-gnu/libns* ${DESTDIR}/lib/i386-linux-gnu/
cp -fpL /usr/lib/libz.so.1 ${DESTDIR}/usr/lib/

######## }}} #######################

echo "> Including cryptoroot.sh into initramfs - SUCCESSFUL"
exit 0

