#!/bin/bash
###################################
# openATV Dreambox InstallUSB 0.1 #
###################################

# Free flash space
rm -rf /usr/lib/gstreamer-1.0
rm -rf /etc/opkg/3rdparty-feed.conf
rm -rf /etc/opkg/dm800se-feed.conf
rm -rf /etc/opkg/dm800se_3rdparty-feed.conf
rm -rf /etc/opkg/all-feed.conf

# Stop E2
init 4

# Install missing tools
opkg update
opkg install dosfstools

umount_usb() {
    for i in 1 2 3 4; do 
        fuser -k $1$i > /dev/null 2>&1
        umount -f $1$i > /dev/null 2>&1
        if [ `mount | grep $1$i | wc -l` -gt 0 ]; then
            echo "Error: cannot unmount $1$i"
            exit 1
        fi
    done
}

prompt_next() {
    echo -e "${GREEN}Press Enter to continue...${NC}"
    read -r
}

GREEN='\033[0;32m'
WHITE_BG='\033[47m'
RED='\033[0;31m'
NC='\033[0m'
NAME=`basename $0`
BOX=`cat /proc/stb/info/model`
URL="http://images.mynonpublic.com/openatv/7.4/dream.php?open=${BOX}"
BOOTNEW=/media/bootnew
ROOTNEW=/media/rootnew

clear
echo -e "\r\n\r\nSet up USB key"
echo -e "${WHITE_BG}${RED}Attention all data on the USB key will be deleted.${NC}"
echo "Please plug a USB key to the ${BOX} and press any key"
prompt_next

# Updated to use /dev/sd? instead of /dev/hd?
DEVICES=`find /dev/sd?`

if [ `echo $DEVICES | grep /dev -c` == "0" ]; then
    echo "Found no devices on ${BOX}"
    sleep 5
    exec "$0" "restarted" "$@"
fi

echo -e "Found: \r\n\r\n$DEVICES\r\n"

# Variable with content
options=($DEVICES)

# Display options with numbers
echo "Select an option:"
for ((i=0; i<${#options[@]}; i++)); do
    printf "%d) %s\n" "$((i+1))" "${options[$i]}"
done

# Prompt for user input
read -p "Enter your choice: " choice

# Validate the choice
if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#options[@]} ]]; then
    selected_option="${options[$((choice-1))]}"
    echo "You chose: $choice: $selected_option"
else
    echo "Invalid choice. Please select a valid option."
    sleep 5
    exec "$0" "restarted" "$@"
fi

prompt_next
SELECTDEV=${selected_option}
SD_SIZE=`sfdisk -l | grep "Disk ${SELECTDEV}" | awk '{print $3}' | sed -e 's/\..*//g'`

if [ `sfdisk -l | grep "Disk ${SELECTDEV}" | grep GiB -c` -gt 0 ] && [ `expr ${SD_SIZE}` -lt 1 ]; then
    echo "Device $DEVICES too small"
    echo "Restart box and use a minimum 1 GB USB key"
    echo "Exit"
    exit 1
fi

/etc/init.d/autofs stop > /dev/null 2>&1
echo "" >/proc/sys/kernel/hotplug
umount_usb ${SELECTDEV}

echo "Partitioning..."
dd if=/dev/zero of=${SELECTDEV} bs=512 count=1

# Updated to use /dev/sdX
sfdisk ${SELECTDEV} << EOF
label: dos
label-id: 0xc041c9d0
device: ${SELECTDEV}
unit: sectors
${SELECTDEV}1 : start=        2048, size=      131072, type=c, bootable
${SELECTDEV}2 : start=      133120, size=      524288, type=82
${SELECTDEV}3 : start=     657408, size=   268435456, type=83
EOF

mkdir -p $BOOTNEW > /dev/null 2>&1
mkdir -p $ROOTNEW > /dev/null 2>&1

echo "Formatting partitions..."
echo -e "${GREEN}Formatting may take some time depending on USB key size.${NC}"
mkfs.vfat -n DREAM-BOOT ${SELECTDEV}1
sleep 3
mount -t vfat ${SELECTDEV}1 $BOOTNEW > /dev/null 2>&1
mkswap ${SELECTDEV}2
swapon ${SELECTDEV}2
yes | mkfs.ext4 -L ROOT ${SELECTDEV}3
mount -t ext4 ${SELECTDEV}3 $ROOTNEW > /dev/null 2>&1

if ! [ `mount | grep $BOOTNEW | wc -l` -gt 0 ] & ! [ `mount | grep $ROOTNEW | wc -l` -gt 0 ]; then
    echo "Error: cannot mount device: ${SELECTDEV}"
    echo "Restart your ${BOX} and start again"
    exit 1
fi

# Install bz2 + boot
echo "Downloading image..."
cd $ROOTNEW
wget -q -U 'Mozilla/13.0 (X11; Linux x86_64; rv:2.0b9pre) Gecko/20230625 Firefox/13.0' -O rootfs.zip $URL > /dev/null 2>&1

# Unpack
echo "Unpacking image..."
unzip rootfs.zip
rm -f rootfs.zip
echo -e "${GREEN}Unpacking may take longer, please be patient...${NC}"
cd $ROOTNEW/${BOX}
bunzip2 rootfs.tar.bz2
tar xvf rootfs.tar -C $ROOTNEW
rm -rf $ROOTNEW/${BOX}

# Update /etc/fstab
sed -ie s!'/dev/mtdblock2'!'# /dev/mtdblock2'!g ${ROOTNEW}/etc/fstab
echo "${SELECTDEV}1	/boot		vfat	ro				0 0" >> ${ROOTNEW}/etc/fstab
echo "${SELECTDEV}2	none		swap	sw				0 0" >> ${ROOTNEW}/etc/fstab

# Install kernel, logo, autoexec_*.bat on boot partition
cp -R ${ROOTNEW}/boot/* ${BOOTNEW}/ > /dev/null 2>&1
rm -f ${BOOTNEW}/autoexec.bat > /dev/null 2>&1
echo "/boot/bootlogo-${BOX}.elf.gz filename=/boot/bootlogo-${BOX}.jpg" > ${BOOTNEW}/autoexec_${BOX}.bat
echo "/boot/vmlinux-3.2-${BOX}.gz root=${SELECTDEV}3 rootdelay=10 rootfstype=ext4 rw console=ttyS0,115200" >> ${BOOTNEW}/autoexec_${BOX}.bat

umount -f $BOOTNEW > /dev/null 2>&1
umount -f $ROOTNEW > /dev/null 2>&1
swapoff ${SELECTDEV}2 > /dev/null 2>&1

echo "Press any key to reboot... (on boot issues: check bootlog via putty)"
echo -e "${GREEN}Don't forget to change the BIOS to boot from USB.${NC}"
prompt_next
reboot
exit 0
