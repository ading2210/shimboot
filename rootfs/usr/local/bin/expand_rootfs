#!/bin/bash

#this script automatically expands the root filesystem

set -e
if [ "$DEBUG" ]; then
  set -x
fi

if [ "$EUID" -ne 0 ]; then
  echo "This needs to be run as root."
  exit 1
fi

root_dev="$(findmnt -T / -no SOURCE)"
luks="$(echo "$root_dev" | grep "/dev/mapper" || true)"

if [ "$luks" ]; then
  echo "Note: Root partition is encrypted."
  kname_dev="$(lsblk --list --noheadings --paths --output KNAME "$root_dev")"
  kname="$(basename "$kname_dev")"
  part_dev="/dev/$(basename "/sys/class/block/$kname/slaves/"*)"
else
  part_dev="$root_dev"
fi

disk_dev="$(lsblk --list --noheadings --paths --output PKNAME "$part_dev" | head -n1)"
part_num="$(echo "${part_dev#$disk_dev}" | tr -d 'p')"

echo "Automatically detected root filesystem:"
fdisk -l "$disk_dev" 2>/dev/null | grep "${disk_dev}:" -A 1
echo
echo "Automatically detected root partition:"
fdisk -l "$disk_dev" 2>/dev/null | grep "${part_dev}"
echo
read -p "Press enter to continue, or ctr+c to cancel. "

echo
echo "Before:"
df -h /

echo
echo "Expanding the partition and filesystem..."
growpart "$disk_dev" "$part_num" || true
if [ "$luks" ]; then
  /bootloader/bin/cryptsetup resize "$root_dev"
fi
resize2fs "$root_dev" || true

echo
echo "After:"
df -h /

echo
echo "Done expanding the root filesystem."
