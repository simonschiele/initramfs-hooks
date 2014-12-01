#!/bin/sh

#
# initramfs hook for decrypting filesystems
# by simon <simon.codingmonkey@googlemail.com>
#

##### Config {{{ ###################

# needed directorys that will be created in initramfs
needed_directories="/usr/sbin/ /var/run/ /var/tmp/ /var/lock /var/log"

# depends that are not installed automatically - optional depends are only used
# if installed on the base system.
depends="/sbin/cryptsetup /sbin/dmsetup"
optional_depends="/sbin/mdadm /bin/mountpoint"

# Hostname for greeting line
hostname="cpad.cnet"

######## }}} #######################

PREREQ="network.sh"

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
        warning "Missing Optional Depends: $dep"
    else
        copy_exec $dep
    fi
done

echo -e "/bin/sh\n/scripts/local-top/cryptroot_block" > ${DESTDIR}/etc/shells
sed -i -e 's@/bin/\(false\|bash\|sh\|zsh\|screen\)@/scripts/local-top/cryptroot_block@g' -e 's|/home/.*:|/var/tmp:|g' ${DESTDIR}/etc/passwd

##### Generate Scripts {{{ #########

# Menu / Blocker Script
cat >${DESTDIR}/scripts/local-top/cryptroot_block << 'EOF'
#!/bin/sh

PREREQ="sshd"

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
    ip=$( ifconfig eth0 2>/dev/null | grep "\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}" | sed 's|.*:\(.*\)\ .*:\(.*\)|\1|g' )
    echo ''
    echo ''
    echo 'Welcome to @hostname@'
    echo ''
    echo "IP: ${ip:-'-'}"
    echo ''
    OLDIFS="$IFS"
    IFS=$'\n'
    for cryptline in $( sed '/^$/d' /etc/crypttab | grep -v "^\ *#" ) 
    do
        cryptname=$( echo "$cryptline" | awk {'print $1'} )
        cryptdevice=$( echo "$cryptline" | awk {'print $2'} )
        echo -n "${cryptname} (${cryptdevice}) is "
        if [ -e /dev/mapper/${cryptname} ]
        then
            echo "unlocked"
        else
            echo "locked"
        fi
    done 
    IFS="$OLDIFS"
    echo ''
    echo 'Available commands:'
    echo ' refresh)         Refresh this menu'
    echo ' unlock)          Decrypt and mount Harddisks'
    echo ' boot)            Continue booting'
    echo ' reboot|halt)     Reboot/Shutdown the System'
    echo ' sh)              Debug Shell'
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
    elif [ $INPUT == 'halt' ] || [ $INPUT == 'shutdown' ] 
    then
        echo "Shutting the system down"
        shutdown
    elif [ $INPUT == 'clear' ] || [ $INPUT == 'refresh' ] || [ $INPUT == 'cls' ]
    then
        clear
        message
    elif [ $INPUT == 'boot' ] || [ $INPUT == 'continue' ]
    then
        clear
        echo "Continue booting..."
        break
    else
        echo "ERROR: unknown command $INPUT"
    fi
done

kill -9 $( cat /tmp/bb_udhcpc.pid ) >/dev/null >&2
killall -9 cryptroot_block >/dev/null >&2
killall -9 dropbear >/dev/null >&2
killall -9 udhcpc >/dev/null >&2
kill -9 $( ps ax | grep udhcp | grep -v grep | awk {'print $1'} ) >/dev/null >&2

EOF
sed -i "s|@hostname@|$hostname|g" ${DESTDIR}/scripts/local-top/cryptroot_block 
chmod 700 ${DESTDIR}/scripts/local-top/cryptroot_block

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
OLDIFS="$IFS"
IFS=$'\n'
for cryptline in $( sed '/^$/d' /etc/crypttab | grep -v "^\ *#" ) 
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
        
        # failover hacks for devices to be recognized as luks
        /sbin/cryptsetup isLuks $cryptdevice >/dev/null 2>&1 
        /sbin/mdadm $cryptdevice >/dev/null 2>&1
        /sbin/mdadm $cryptdevice >/dev/null 2>&1
        /sbin/mdadm $cryptdevice >/dev/null 2>&1

        if [ -e /dev/mapper/${cryptname} ]
        then
            echo "Device already unlocked"
        else
            echo "Decrypting device ${cryptdevice} as ${cryptname}."
            if ( /sbin/cryptsetup -T 10 luksOpen ${cryptdevice} ${cryptname} )
            then
                echo "$cryptname (${cryptdevice}) unlocked."
                break
            else
                echo "Could not unlock ${cryptname} (${cryptdevice})."
                sleep 5
            fi
        fi
    fi
done
IFS="$OLDIFS"

exit 0

EOF
chmod 700 ${DESTDIR}/bin/decrypt


######## }}} #######################

##### copy depends {{{ #########

if [ -e /etc/mdadm/mdadm.conf ]
then
    mkdir -p ${DESTDIR}/etc/mdadm/
    cp -fpL /etc/mdadm/mdadm.conf ${DESTDIR}/etc/mdadm/
fi
cp -fpL /etc/fstab ${DESTDIR}/etc/
cp -fpL /etc/crypttab ${DESTDIR}/etc/

######## }}} #######################

echo "> Including cryptoroot.sh into initramfs - SUCCESSFUL"
exit 0

