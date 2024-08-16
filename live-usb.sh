#!/bin/bash

################################################################################
## This script is supposed to be started by install.sh on Arch Linux Live ISO ##
##                      DO NOT RUN THIS SCRIPT DIRECTLY!                      ##
################################################################################

# Exit on error
set -euo pipefail

# Check boot type - (not used yet)
if [ -d /sys/firmware/efi ]; then
    BOOT_TYPE="UEFI"
else
    BOOT_TYPE="BIOS"
    # exit
    echo "This script only supports UEFI boot";
    exit 1;
fi

# Set the keyboard layout
echo "1.0 - Do you want to set a keyboard layout? (y/N)"
read -r NEEDS_KEYBOARD
if [ "$NEEDS_KEYBOARD" = "y" ]; then
    echo "1.1 - Do you need to see a list of available keyboard layouts before choosing? (y/N)"
    read -r NEEDS_KEYBOARD_LIST
    if [ "$NEEDS_KEYBOARD_LIST" = "y" ]; then
        localectl list-keymaps
    fi
    echo "1.2 - Please enter your keyboard layout (e.g. us, de, fr, ...):"
    read KEYBOARD_LAYOUT
    loadkeys $KEYBOARD_LAYOUT
fi

# Set the system clock
echo "2.0 - Do you want to set the system clock? (y/N)"
read -r NEEDS_CLOCK
if [ "$NEEDS_CLOCK" = "y" ]; then
    echo "2.1 - Do you need to see a list of available time zones before choosing? (y/N)"
    read -r NEEDS_TIMEZONES
    if [ "$NEEDS_TIMEZONES" = "y" ]; then
        timedatectl list-timezones
    fi
    echo "2.2 - Please enter your time zone (e.g. Europe/Berlin) Enter \"n\" to skip:"
    read TIME_ZONE
    if [ "$TIME_ZONE" != "n" ]; then
        timedatectl set-timezone $TIME_ZONE
    fi
    timedatectl set-ntp true
fi

# Partition the disks
echo "--- DISKS ---"
lsblk
## Ask for the disk to install on
echo "3.0 - Please enter the disk to install Arch Linux on (e.g. /dev/sda):"
read DISK

echo "Any data on $DISK will be lost. Do you want to continue? (y/N)"
read -r DATA_LOSS_CONFIRM
if [ "$DATA_LOSS_CONFIRM" != "y" ]; then
    exit 1
fi

## Clean disk
echo "3.1 - Do you want to wipe the disk? (executes \`dd if=/dev/zero of=$DISK bs=1M count=100\`) (y/N)"
read -r NEEDS_CLEAN_DISK
if [ "$NEEDS_CLEAN_DISK" = "y" ]; then
    echo "This might take a while..."
    dd if=/dev/zero of="$DISK" bs=1M count=100
fi

## Ask for boot partition size
echo "3.2 - Please enter the boot partition size (e.g. 512M):"
read BOOT_SIZE

## Partition disk into boot and root
### mklabel gpt
parted -s "$DISK" mklabel gpt

### Create boot partition
parted -s "$DISK" mkpart ESP fat32 1MiB "$BOOT_SIZE"
parted -s "$DISK" set 1 esp on

### Create LUKS partition
parted -s "$DISK" mkpart primary ext4 "$BOOT_SIZE" 100%

### Detect the partitions
BOOT_PARTITION=$(ls "$DISK"* | tail +2 | head -n 1)
LUKS_PARTITION=$(ls "$DISK"* | tail +3 | head -n 1)

mkfs.fat -F32 "$BOOT_PARTITION"

## Ask for swap
echo "3.3 - Do you want to have a swap partition? (y/N)"
read -r NEEDS_SWAP
if [ "$NEEDS_SWAP" = "y" ]; then
    ## Ask for swap partition size
    echo "3.3.1 - Please enter the swap partition size (e.g. 4G, 8G):"
    read SWAP_SIZE
fi

## Ask for seperate home partition
echo "3.4 - Do you want to have a separate home partition? (y/N)"
read -r NEEDS_SEPERATE_HOME
if [ "$NEEDS_SEPERATE_HOME" = "y" ]; then
    ## Ask for home partition size
    echo "3.4.1 - Please enter the home partition size (e.g. 20G, 100G):"
    read HOME_SIZE
fi

## Create cryptlvm
echo "-- cryptsetup luksFormat \"$LUKS_PARTITION\" --"
cryptsetup luksFormat "$LUKS_PARTITION"
echo "-- cryptsetup open \"$LUKS_PARTITION\" cryptlvm --"
cryptsetup open "$LUKS_PARTITION" cryptlvm

pvcreate /dev/mapper/cryptlvm
vgcreate vg0 /dev/mapper/cryptlvm

### Create swap
if [ "$NEEDS_SWAP" = "y" ]; then
    lvcreate -L "$SWAP_SIZE" vg0 -n swap
    mkswap /dev/mapper/vg0-swap
fi
### Create home
if [ "$NEEDS_SEPERATE_HOME" = "y" ]; then
    lvcreate -L "$HOME_SIZE" vg0 -n home
    mkfs.ext4 /dev/mapper/vg0-home
fi
### Create root
lvcreate -l 100%FREE vg0 -n root
mkfs.ext4 /dev/mapper/vg0-root

## Mount the file systems
### Mount root
mount /dev/mapper/vg0-root /mnt
### Mount boot
mkdir -p /mnt/boot
mount "$BOOT_PARTITION" /mnt/boot
### Mount home
if [ "$NEEDS_SEPERATE_HOME" = "y" ]; then
    mkdir -p /mnt/home
    mount /dev/mapper/vg0-home /mnt/home
fi
### Swap on
if [ "$NEEDS_SWAP" = "y" ]; then
    swapon /dev/mapper/vg0-swap
fi

## Show the disk layout
lsblk

echo "Is it correct? (y/N)"
read -r DISK_LAYOUT_CONFIRM
if [ "$DISK_LAYOUT_CONFIRM" != "y" ]; then
    exit 1
fi

PACKAGES_TO_INSTALL="base base-devel linux linux-headers linux-firmware efibootmgr lvm2 iwd refind os-prober intel-ucode networkmanager"
echo "Packages to install: $PACKAGES_TO_INSTALL"
echo "Do you want to install additional packages? (y/N)"
read -r NEEDS_ADDITIONAL_PACKAGES
if [ "$NEEDS_ADDITIONAL_PACKAGES" = "y" ]; then
    echo "Please enter the additional packages (e.g. vim, git, ...):"
    read ADDITIONAL_PACKAGES
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $ADDITIONAL_PACKAGES"
fi

## Install
pacstrap -K /mnt $PACKAGES_TO_INSTALL

## refind-install hook
cat <<EOF >/etc/pacman.d/hooks/refind.hook
[Trigger]
Operation=Upgrade
Type=Package
Target=refind

[Action]
Description = Updating rEFInd on ESP
When=PostTransaction
Exec=/usr/bin/refind-install
EOF

## Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Run chroot script
cp chroot.sh /mnt
arch-chroot /mnt ./chroot.sh

# Set /etc/localtime, /etc/vconsole.conf and /etc/hostname
if [ -n "$KEYBOARD_LAYOUT" ]; then
    echo "KEYMAP=$KEYBOARD_LAYOUT" > /mnt/etc/vconsole.conf
fi

if [ -n "$TIME_ZONE" ]; then
    ln -sf "/mnt/usr/share/zoneinfo/$TIME_ZONE" /mnt/etc/localtime
fi

echo "Please enter your hostname:"
read HOSTNAME
echo "$HOSTNAME" > /mnt/etc/hostname

# rEFInd settings
LUKS_UUID=$(blkid -s UUID -o value "$LUKS_PARTITION")

BLK_OPTIONS="cryptdevice=UUID=${LUKS_UUID}:cryptlvm root=/dev/vg0/root"
RW_LOGLEVEL="rw loglevel=3"
INITRD="initrd=intel-ucode.img initrd=initramfs-%v.img"

cat <<EOF >/mnt/boot/refind_linux.conf
"Arch Linux - Hybrid"              "${BLK_OPTIONS} ${RW_LOGLEVEL} ${INITRD} optimus-manager.startup=hybrid"
"Arch Linux - NVIDIA"              "${BLK_OPTIONS} ${RW_LOGLEVEL} ${INITRD} optimus-manager.startup=nvidia"
"Arch Linux - Integrated"          "${BLK_OPTIONS} ${RW_LOGLEVEL} ${INITRD} optimus-manager.startup=integrated"
"Arch Linux - standard options"    "${BLK_OPTIONS} ${RW_LOGLEVEL} ${INITRD}"
"Arch Linux - fallback initramfs"  "${BLK_OPTIONS} ${RW_LOGLEVEL} initrd=intel-ucode.img initrd=initramfs-%v-fallback.img"
"Arch Linux - terminal"            "${BLK_OPTIONS} ${RW_LOGLEVEL} ${INITRD} systemd.unit=multi-user.target"
"Arch Linux - single-user mode"    "${BLK_OPTIONS} ${RW_LOGLEVEL} ${INITRD} single"
"Arch Linux - minimal options"     "${BLK_OPTIONS} ${INITRD} ro"
EOF

sed -i 's|#extra_kernel_version_strings|extra_kernel_version_strings|' /mnt/boot/EFI/refind/refind.conf
sed -i 's|#fold_linux_kernels|fold_linux_kernels|' /mnt/boot/EFI/refind/refind.conf

umount /mnt/boot
if [ "$NEEDS_SEPERATE_HOME" = "y" ]; then
    umount /mnt/home
fi
if [ "$NEEDS_SWAP" = "y" ]; then
    swapoff /dev/mapper/vg0-swap
fi