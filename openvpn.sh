#!/bin/sh

#
# initramfs hook that includes openvpn.
# by simon <simon.codingmonkey@googlemail.com>
#

##### Config {{{ ###################

# needed directorys that will be created in initramfs
needed_directories="/usr/sbin/"

# depends that are not installed automatically - optional depends are only used
# if installed on the base system.
depends="/usr/sbin/openvpn"
optional_depends=""

openvpn_config="/etc/openvpn/nerdmail/client.conf"
openvpn_dir="/etc/openvpn/nerdmail/"

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
echo "> Including OpenVPN into initramfs"

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

##### Generate Scripts {{{ #########

# startscript for openvpn 
cat >${DESTDIR}/scripts/local-top/openvpn << 'EOF'
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

echo "Starting OpenVPN daemon."
cd @openvpn_dir@
openvpn --daemon --config @openvpn_config@

EOF
sed -i "s|@openvpn_config@|$openvpn_config|g" ${DESTDIR}/scripts/local-top/openvpn
sed -i "s|@openvpn_dir@|$openvpn_dir|g" ${DESTDIR}/scripts/local-top/openvpn
chmod 700 ${DESTDIR}/scripts/local-top/openvpn

######## }}} #######################

##### Extended Depends  #########
cp -rfpL /etc/openvpn/ ${DESTDIR}/etc/ 

echo "> Including OpenVPN into initramfs - SUCCESSFUL"
exit 0

