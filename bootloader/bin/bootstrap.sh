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

rescue_mode=""

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

#get a partition block device from a disk path and a part number
get_part_dev() {
  local disk="$1"
  local partition="$2"

  #disk paths ending with a number will have a "p" before the partition number
  last_char="$(echo -n "$disk" | tail -c 1)"
  if [ "$last_char" -eq "$last_char" ] 2>/dev/null; then
    echo "${disk}p${partition}"
  else
    echo "${disk}${partition}"
  fi
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
      get_part_dev "$disk" "$partition"
    done
  done
}

find_chromeos_partitions() {
  local roota_partitions="$(cgpt find -l ROOT-A)"
  local rootb_partitions="$(cgpt find -l ROOT-B)"

  if [ "$roota_partitions" ]; then
    for partition in $roota_partitions; do
      echo "${partition}:ChromeOS_ROOT-A:CrOS"
    done
  fi
  
  if [ "$rootb_partitions" ]; then
    for partition in $rootb_partitions; do
      echo "${partition}:ChromeOS_ROOT-B:CrOS"
    done
  fi
}

find_all_partitions() {
  echo "$(find_chromeos_partitions)"
  echo "$(find_rootfs_partitions)"
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
  local shimboot_version="$(cat /opt/.shimboot_version)"
  if [ -f "/opt/.shimboot_version_dev" ]; then
    local git_hash="$(cat /opt/.shimboot_version_dev)"
    local suffix="-dev-$git_hash"
  fi
  cat << EOF 
Shimboot ${shimboot_version}${suffix}

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

print_selector() {
  local rootfs_partitions="$1"
  local i=1

  echo "┌──────────────────────┐"
  echo "│ Shimboot OS Selector │"
  echo "└──────────────────────┘"

  # Check if there are bootable partitions
  if [ -n "${rootfs_partitions}" ]; then
    # Process each rootfs partition entry
    for rootfs_partition in $rootfs_partitions; do
      # Use IFS to split the string, separating by `:`
      IFS=':' read -r part_path part_name _ <<< "$rootfs_partition"
      echo "${i}) ${part_name} on ${part_path}"
      i=$((i + 1))
    done
  else
    echo "No bootable partitions found. Refer to the Shimboot documentation to mark a partition as bootable."
  fi

  echo "Options:"
  echo "  q) Reboot"
  echo "  s) Enter a shell"
  echo "  l) View license"
}

get_selection() {
  local rootfs_partitions="$1"
  local i=1

  read -p "Your selection: " selection
  if [ "$selection" = "q" ]; then
    echo "Rebooting now."
    reboot -f
  elif [ "$selection" = "s" ]; then
    reset
    enable_debug_console "$TTY1"
    return 0
  elif [ "$selection" = "l" ]; then
    clear
    print_license
    echo
    read -p "Press [enter] to return to the bootloader menu"
    return 1
  fi

  local selection_cmd="${selection%% *}"
  if [ "$selection_cmd" = "rescue" ]; then
    selection="${selection#* }"
    rescue_mode="1"
  else
    rescue_mode=""
  fi

  for rootfs_partition in $rootfs_partitions; do
    IFS=':' read -r part_path part_name part_flags <<< "$rootfs_partition"

    if [ "$selection" = "$i" ]; then
      echo "Selected $part_path"
      if [ "$part_flags" = "CrOS" ]; then
        echo "Booting Chrome OS partition"
        print_donor_selector "$rootfs_partitions"
        get_donor_selection "$rootfs_partitions" "$part_path"
      else
        boot_target "$part_path"
      fi
      return 1
    fi

    i=$((i+1))
  done
  
  echo "Invalid selection"
  sleep 1
  return 1
}

copy_progress() {
  local source="$1"
  local destination="$2"
  mkdir -p "$destination"
  tar -cf - -C "${source}" . | pv -f | tar -xf - -C "${destination}"
}

print_donor_selector() {
  local rootfs_partitions="$1"
  local i=1;

  echo "Choose a partition to copy firmware and modules from:"

  for rootfs_partition in $rootfs_partitions; do
    IFS=':' read -r part_path part_name part_flags <<< "$rootfs_partition"

    if [ "$part_flags" = "CrOS" ]; then
      continue
    fi

    echo "${i}) ${part_name} on ${part_path}"
    i=$((i+1))
  done
}

yes_no_prompt() {
  local prompt="$1"
  local var_name="$2"

  while true; do
    read -p "$prompt" temp_result

    if [ "$temp_result" = "y" ] || [ "$temp_result" = "n" ]; then
      #the busybox shell has no other way to declare a variable from a string
      #the declare command and printf -v are both bashisms
      eval "$var_name='$temp_result'"
      return 0
    else
      echo "Invalid selection"
    fi
  done
}

get_donor_selection() {
  local rootfs_partitions="$1"
  local target="$2"
  local i=1
  read -p "Your selection: " selection

  for rootfs_partition in $rootfs_partitions; do
    IFS=':' read -r part_path part_name part_flags <<< "$rootfs_partition"

    if [ "$part_flags" = "CrOS" ]; then
      continue
    fi

    if [ "$selection" = "$i" ]; then
      echo "Selected $part_path as the donor partition"
      yes_no_prompt "Would you like to spoof verified mode? This is useful if you're planning on using Chrome OS while enrolled. (y/n): " use_crossystem
      yes_no_prompt "Would you like to spoof an invalid HWID? This will forcibly prevent the device from being enrolled. (y/n): " invalid_hwid
      boot_chromeos "$target" "$part_path" "$use_crossystem" "$invalid_hwid"
    fi

    i=$((i+1))
  done

  echo "Invalid selection"
  sleep 1
  return 1
}

exec_init() {
  if [ "$rescue_mode" = "1" ]; then
    echo "Entering a rescue shell instead of starting init"
    echo "Once you are done fixing whatever is broken, run 'exec /sbin/init' to continue booting the system normally"
    
    if [ -f "/bin/bash" ]; then
      exec /bin/bash < "$TTY1" >> "$TTY1" 2>&1
    else
      exec /bin/sh < "$TTY1" >> "$TTY1" 2>&1
    fi
  else
    exec /sbin/init < "$TTY1" >> "$TTY1" 2>&1
  fi
}

boot_target() {
  local target="$1"

  echo "Preparing new root environment"
  mkdir /newroot
  mount $target /newroot
  # Bind mount /dev/console to show systemd boot messages
  if [ -f "/bin/frecon-lite" ]; then 
    rm -f /dev/console
    touch /dev/console # This must be a regular file or the system crashes
    mount -o bind "$TTY1" /dev/console
  fi
  move_mounts /newroot

  echo "Switching root"
  mkdir -p /newroot/bootloader
  pivot_root /newroot /newroot/bootloader
  exec_init
}

boot_chromeos() {
  local target="$1"
  local donor="$2"
  local use_crossystem="$3"
  local invalid_hwid="$4"
  
  echo "Mounting target"
  mkdir /newroot
  mount -o ro $target /newroot

  echo "Mounting tmpfs"
  mount -t tmpfs -o mode=1777 none /newroot/tmp
  mount -t tmpfs -o mode=0555 run /newroot/run
  mkdir -p -m 0755 /newroot/run/lock

  echo "Mounting donor partition"
  local donor_mount="/newroot/tmp/donor_mnt"
  local donor_files="/newroot/tmp/donor"
  mkdir -p $donor_mount
  mount -o ro $donor $donor_mount

  echo "Copying modules and firmware to tmpfs (this may take a while)"
  copy_progress $donor_mount/lib/modules $donor_files/lib/modules
  copy_progress $donor_mount/lib/firmware $donor_files/lib/firmware
  mount -o bind $donor_files/lib/modules /newroot/lib/modules
  mount -o bind $donor_files/lib/firmware /newroot/lib/firmware
  umount $donor_mount
  rm -rf $donor_mount

  if [ -e "/newroot/etc/init/tpm-probe.conf" ]; then
    echo "Applying Chrome OS Flex patches"
    mkdir -p /newroot/tmp/empty
    mount -o bind /newroot/tmp/empty /sys/class/tpm

    cat /newroot/etc/lsb-release | sed "s/DEVICETYPE=OTHER/DEVICETYPE=CHROMEBOOK/" > /newroot/tmp/lsb-release
    mount -o bind /newroot/tmp/lsb-release /newroot/etc/lsb-release
  fi

  echo "Patching Chrome OS rootfs"
  cat /newroot/etc/ui_use_flags.txt | sed "/reven_branding/d" | sed "/os_install_service/d" > /newroot/tmp/ui_use_flags.txt
  mount -o bind /newroot/tmp/ui_use_flags.txt /newroot/etc/ui_use_flags.txt

  cp /opt/mount-encrypted /newroot/tmp/mount-encrypted
  cp /newroot/usr/sbin/mount-encrypted /newroot/tmp/mount-encrypted.real
  mount -o bind /newroot/tmp/mount-encrypted /newroot/usr/sbin/mount-encrypted
  
  cat /newroot/etc/init/boot-splash.conf | sed '/^script$/a \  pkill frecon-lite || true' > /newroot/tmp/boot-splash.conf
  mount -o bind /newroot/tmp/boot-splash.conf /newroot/etc/init/boot-splash.conf
  
  if [ "$use_crossystem" = "y" ]; then
    echo "Patching crossystem"
    cp /opt/crossystem /newroot/tmp/crossystem
    if [ "$invalid_hwid" = "y" ]; then
      sed -i 's/block_devmode/hwid/' /newroot/tmp/crossystem
    fi

    cp /newroot/usr/bin/crossystem /newroot/tmp/crossystem_old
    mount -o bind /newroot/tmp/crossystem /newroot/usr/bin/crossystem
  fi

  echo "Moving mounts"
  move_mounts /newroot

  echo "Switching root"
  mkdir -p /newroot/tmp/bootloader
  pivot_root /newroot /newroot/tmp/bootloader

  echo "Starting init"
  /sbin/modprobe zram
  exec_init
}

main() {
  echo "Starting the Shimboot bootloader"

  enable_debug_console "$TTY2"

  local valid_partitions="$(find_all_partitions)"

  while true; do
    clear
    print_selector "${valid_partitions}"

    if get_selection "${valid_partitions}"; then
      break
    fi
  done
}

trap - EXIT
main "$@"
sleep 1d
