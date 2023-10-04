#!/bin/busybox sh
# Copyright 2015 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# To bootstrap the factory installer on rootfs. This file must be executed as
# PID=1 (exec).
# Note that this script uses the busybox shell (not bash, not dash).

#original: https://chromium.googlesource.com/chromiumos/platform/initramfs/+/refs/heads/main/factory_shim/bootstrap.sh

set -x

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
    echo "${disk}${partitions}"
  done
}

#from original bootstrap.sh
move_mounts() {
  local BASE_MOUNTS="/sys /proc /dev"
  local NEWROOT_MNT="$1"
  for mnt in $BASE_MOUNTS; do
    # $mnt is a full path (leading '/'), so no '/' joiner
    mkdir -p "$NEWROOT_MNT$mnt"
    mount -n -o move "$mnt" "$NEWROOT_MNT$mnt"
  done
}

#from original bootstrap.sh
use_new_root() {
  local NEWROOT_MNT="$1"
  move_mounts $NEWROOT_MNT
  # Chroot into newroot, erase the contents of the old /, and exec real init.
  echo "About to switch root... Check VT2/3/4 if you stuck for a long time."
  # If you have problem getting console after switch_root, try to debug by:
  #  1. Try a simple shell.
  #     exec <"${TTY}" >"${TTY}" 2>&1
  #     exec switch_root "${NEWROOT_MNT}" /bin/sh
  #  2. Try to invoke factory installer directly
  #     exec switch_root "${NEWROOT_MNT}" /usr/sbin/factory_shim_service.sh
  # -v prints upstart info in kmsg (available in INFO_TTY).
  exec switch_root "${NEWROOT_MNT}" /sbin/init
}

main() {
  echo "...:::||| Bootstrapping ChromeOS Factory Shim |||:::..."
  echo "TTY: ${TTY}, LOG: ${LOG_TTY}, echo: ${echo_TTY}, DEBUG: ${DEBUG_TTY}"
  echo "idk please work"

  sleep 5
  
  local rootfs_partitions=$(find_rootfs_partitions)
  for rootfs_partition in $rootfs_partitions; do
    local IFS=: read -r part_path part_name <<< $rootfs_partition
    echo "found bootable partition ${part_path}: ${part_name}"
  done
  
  sleep 5

  mkdir /newroot
  mount /dev/sda4 /newroot
  use_new_root /newroot

  enable_debug_console "/dev/pts/0"
}

main "$@"
sleep 1d