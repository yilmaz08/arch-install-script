#!/bin/bash

################################################################################
## This script is supposed to be started by install.sh on Arch Linux Live ISO ##
##                      DO NOT RUN THIS SCRIPT DIRECTLY!                      ##
################################################################################

# Exit on error
set -euo pipefail

# Set the locale
sed -i -e 's|#en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# set root password
echo "-- Set root password"
passwd

# configure mkinitcpio
sed -i '/^HOOKS/s/\(block \)\(.*filesystems\)/\1encrypt lvm2 \2/' /etc/mkinitcpio.conf

mkinitcpio -P linux

# install refind
refind-install

systemctl enable NetworkManager