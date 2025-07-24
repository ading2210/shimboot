#!/bin/bash

set -e

IMG_FILE="arch.img"
IMG_URL="https://drive.usercontent.google.com/download?id=17cKas5LLbgsCZgOFMNpV4GPok1wDbV6r&export=download&confirm=yes"

# Check if image already exists
if [ -f "$IMG_FILE" ]; then
    echo "$IMG_FILE already exists. Skipping download."
else
    echo "Downloading Arch Linux image..."
    wget "$IMG_URL" -O "$IMG_FILE"
fi

# List block devices
echo "Available block devices:"
lsblk

# Prompt user for target partition
echo
read -p "Enter the full path of the target partition to flash (e.g., /dev/sdX): " target

# Confirm selection
echo "You entered: $target"
read -p "Are you sure you want to flash $IMG_FILE to $target? This will erase all data on the target. (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

# Flash the image
echo "Flashing image to $target..."
sudo dd if="$IMG_FILE" of="$target" bs=4M status=progress conv=fsync

echo "Done."
