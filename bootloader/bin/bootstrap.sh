#!/bin/busybox sh
# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# To bootstrap the factory installer on rootfs. This file must be executed as
# PID=1 (exec).
# Note that this script uses the busybox shell (not bash, not dash).

#original: https://chromium.googlesource.com/chromiumos/platform/initramfs/+/refs/heads/main/factory_shim/bootstrap.sh

#set -x
set +x

invoke_terminal() {
  local tty="$1"
  local title="$2"
  shift
  shift
  # Copied from factory_installer/factory_shim_service.sh.
  echo "${title}" >>${tty}
  setsid sh -c "exec script -afqc '$*' /dev/null <${tty} >>${tty} 2>&1 &"
}

enable_debug_console() {
  local tty="$1"
  echo -e '\033[1;33m[cros_debug] enabled on '${tty}'.\033[m'
  invoke_terminal "${tty}" "[Bootstrap Debug Console]" "/bin/busybox sh"
}

find_rootfs_partitions() {
  local disks=$(fdisk -l | sed -n "s/Disk \(\/dev\/.*\):.*/\1/p")
  if [ ! "${disks}" ]; then
    return 1
  fi

  for disk in $disks; do
    local partitions=$(fdisk -l $disk | sed -n "s/^[ ]\+\([0-9]\+\).*shimboot_rootfs:\(.*\)$/\1:\2/p")
    if [ ! "${partitions}" ]; then
      continue
    fi
    for partition in $partitions; do
      echo "${disk}${partition}"
    done
  done
}

#from original bootstrap.sh
move_mounts() {
  local base_mounts="/sys /proc /dev"
  local newroot_mnt="$1"
  for mnt in $base_mounts; do
    # $mnt is a full path (leading '/'), so no '/' joiner
    mkdir -p "$newroot_mnt$mnt"
    mount -n -o move "$mnt" "$newroot_mnt$mnt"
  done
}

print_selector() {
  local rootfs_partitions="$1"
  local i=1

  echo "┌──────────────────────┐"
  echo "│ Shimboot OS Selector │"
  echo "└──────────────────────┘"

  if [ "${rootfs_partitions}" ]; then
    for rootfs_partition in $rootfs_partitions; do
      #i don't know of a better way to split a string in the busybox shell
      local part_path=$(echo $rootfs_partition | cut -d ":" -f 1)
      local part_name=$(echo $rootfs_partition | cut -d ":" -f 2)
      echo "${i}) ${part_name} on ${part_path}"
      i=$((i+1))
    done
  else
    echo "no bootable partitions found. please see the shimboot documentation to mark a partition as bootable."
  fi

  echo "q) reboot"
  echo "s) enter a shell"
}

get_selection() {
  local rootfs_partitions="$1"
  local i=1

  read -p "Your selection: " selection
  if [ "$selection" = "q" ]; then
    echo "rebooting now."
    reboot -f
  elif [ "$selection" = "s" ]; then
    reset
    enable_debug_console "/dev/pts/0"
    return 0
  fi

  for rootfs_partition in $rootfs_partitions; do
    local part_path=$(echo $rootfs_partition | cut -d ":" -f 1)
    local part_name=$(echo $rootfs_partition | cut -d ":" -f 2)

    if [ "$selection" = "$i" ]; then
      echo "selected $part_path"
      sleep 2
      boot_target $part_path
      return 0
    fi

    i=$((i+1))
  done
  
  echo "invalid selection"
  return 1
}

boot_target() {
  local target="$1"
  #scuffed way to get init to output to the right tty
  #x11 doesn't use tty1 anyways so this shouldn't cause issues
  mount -o bind /dev/pts/0 /dev/tty1

  echo "moving mounts to newroot"
  mkdir /newroot
  mount $target /newroot
  move_mounts /newroot

  echo "switching root"
  mkdir -p /newroot/bootloader
  pivot_root /newroot /newroot/bootloader
  local tty="/dev/pts/0"
  exec /sbin/init 5 < "$tty" >> "$tty" 2>&1
}

main() {
  echo "...:::||| Bootstrapping ChromeOS Factory Shim |||:::..."
  echo "idk please work"

  enable_debug_console "/dev/pts/1"

  local rootfs_partitions=$(find_rootfs_partitions)

  while true; do
    clear
    print_selector "${rootfs_partitions}"
    if get_selection "${rootfs_partitions}"; then
      break
    fi
    sleep 2
  done
}

trap - EXIT
main "$@"
sleep 1d
