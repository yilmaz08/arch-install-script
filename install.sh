#!/bin/bash

set -euo pipefail

if ping -q -c 1 -W 1 archlinux.org > /dev/null; then
    echo "Connected to the internet"
else
    echo "Please connect to the internet... (try iwctl)"
    exit 1
fi

BASE_URL="https://raw.githubusercontent.com/yilmaz08/arch-install-script/main/"
LIVE_USB_SCRIPT="live-usb.sh"
CHROOT_SCRIPT="chroot.sh"

echo "Downloading scripts..."
curl -s -o "$LIVE_USB_SCRIPT" "$BASE_URL$LIVE_USB_SCRIPT"
curl -s -o "$CHROOT_SCRIPT" "$BASE_URL$CHROOT_SCRIPT"

echo "Scripts downloaded successfully"

chmod +x "$LIVE_USB_SCRIPT"
chmod +x "$CHROOT_SCRIPT"

echo "Press Enter to start the installation..."
read -r

./live-usb.sh

echo "Installation complete. Reboot the system."