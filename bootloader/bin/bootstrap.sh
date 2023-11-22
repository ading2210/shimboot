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
  echo -e "debug console enabled on ${tty}"
  invoke_terminal "${tty}" "[Bootstrap Debug Console]" "/bin/busybox sh"
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

print_license() {
  cat << EOF 
ading2210/shimboot: Boot desktop Linux from a Chrome OS RMA shim.
Copyright (C) 2023 ading2210

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
EOF
}

copy_progress() {
  local source="$1"
  local destination="$2"
  mkdir -p "$destination"
  tar -cf - -C "${source}" . | pv -f | tar -xf - -C "${destination}"
}

boot_target() {
  local target="$1"

  echo "moving mounts to newroot"
  mkdir /newroot
  mount $target /newroot
  move_mounts /newroot

  echo "switching root"
  mkdir -p /newroot/bootloader
  pivot_root /newroot /newroot/bootloader
  exec /sbin/init < "$TTY1" >> "$TTY1" 2>&1
}

boot_chromeos() {
  local target="$1"
  local donor="$2"
  local use_crossystem="$3"

  echo "mounting target"
  mkdir /newroot
  mount -o ro $target /newroot

  echo "mounting tmpfs"
  mount -t tmpfs -o mode=1777 none /newroot/tmp
  mount -t tmpfs -o mode=0555 run /newroot/run
  mkdir -p -m 0755 /newroot/run/lock

  echo "mounting donor partition"
  local donor_mount="/newroot/tmp/donor_mnt"
  local donor_files="/newroot/tmp/donor"
  mkdir -p $donor_mount
  mount -o ro $donor $donor_mount

  echo "copying modules and firmware to tmpfs (this may take a while)"
  copy_progress $donor_mount/lib/modules $donor_files/lib/modules
  copy_progress $donor_mount/lib/firmware $donor_files/lib/firmware
  mount -o bind $donor_files/lib/modules /newroot/lib/modules
  mount -o bind $donor_files/lib/firmware /newroot/lib/firmware
  umount $donor_mount
  rm -rf $donor_mount

  if [ -e "/newroot/etc/init/tpm-probe.conf" ]; then
    echo "applying chrome os flex patches"
    mkdir -p /newroot/tmp/empty
    mount -o bind /newroot/tmp/empty /sys/class/tpm

    cat /newroot/etc/lsb-release | sed "s/DEVICETYPE=OTHER/DEVICETYPE=CHROMEBOOK/" > /newroot/tmp/lsb-release
    mount -o bind /newroot/tmp/lsb-release /newroot/etc/lsb-release
  fi

  echo "patching chrome os rootfs"
  cat /newroot/etc/ui_use_flags.txt | sed "/reven_branding/d" | sed "/os_install_service/d" > /newroot/tmp/ui_use_flags.txt
  mount -o bind /newroot/tmp/ui_use_flags.txt /newroot/etc/ui_use_flags.txt
  
  if [ "$use_crossystem" = "y" ]; then
    echo "patching crossystem"
    cp /opt/crossystem /newroot/tmp/crossystem
    cp /newroot/usr/bin/crossystem /newroot/tmp/crossystem_old
    mount -o bind /newroot/tmp/crossystem /newroot/usr/bin/crossystem
  fi

  echo "moving mounts"
  move_mounts /newroot

  echo "switching root"
  mkdir -p /newroot/tmp/bootloader
  pivot_root /newroot /newroot/tmp/bootloader

  echo "starting init"
  /sbin/modprobe zram
  pkill frecon-lite
  exec /sbin/init < "$TTY1" >> "$TTY1" 2>&1
}

main() {
  echo "starting the shimboot bootloader"
  enable_debug_console "$TTY2"

  echo "extracting terminfo"
  cd /etc
  unzip -q terminfo.zip
  cd /

  echo "launching python bootloader"
  while true; do
    python3 /opt/main.py
    local exit_code="$?"
    
    #boot an option
    if [ "$exit_code" = "0" ]; then
      chmod +x /tmp/bootloader_result
      . /tmp/bootloader_result
    elif [ "$exit_code" = "1" ]; then
      read -s -p "An unexpected error occured. Press [enter] to run the bootloader again."
    fi
  done
}

trap - EXIT
main "$@"
sleep 1d
