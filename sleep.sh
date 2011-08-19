#!/bin/sh

#
# initramfs hook for blocking boot procedure for a specific time
# by simon <simon.codingmonkey@googlemail.com>
#

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

case $1 in
    prereqs)
        prereqs
        exit 0
    ;;
esac

. /usr/share/initramfs-tools/hook-functions
echo "> Including sleep.sh into initramfs"

cat >${DESTDIR}/scripts/local-top/sleep << 'EOF'
#!/bin/sh

TIMER=300
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

for cmd in $( cat /proc/cmdline )
do 
    if ( echo "$cmd" | grep -q "initramfs-sleep=" )
    then
        sleeptime=$( echo "$cmd" | cut -f'2' -d'=' | sed 's|[^0-9]||g' )
        if [ -n "$sleeptime" ]
        then
            TIMER=$sleeptime
        fi
    fi
done

i=0
j=0
echo "Starting initramfs sleep for $TIMER seconds..."
while [ $i -lt $TIMER ]
do
    i=$(( $i + 1 ))
    j=$(( $j + 1 ))
    sleep 1
    if [ $j -eq 10 ]
    then
        j=0
        echo "Sleept $i seconds. Continue Booting in $(( $TIMER - $i )) seconds."
    fi
done
echo "Continue Booting after initramfs sleep."

EOF
chmod 700 ${DESTDIR}/scripts/local-top/sleep

echo "> Including sleep.sh into initramfs - SUCCESSFUL"
exit 0

