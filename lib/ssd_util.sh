#!/bin/sh
#original: https://github.com/MercuryWorkshop/sh1mmer/blob/beautifulworld/wax/lib/ssd_util.sh

# this is a modified version of make_dev_ssd from cros. it allows the script to be run on any linux device and adds extra utility

#
# Copyright (c) 2012 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This script can change key (usually developer keys) and kernel config
# of kernels on an disk image (usually for SSD but also works for USB).

SCRIPT_BASE="$(dirname "$0")"
. "$SCRIPT_BASE/common_minimal.sh"
load_shflags || exit 1

# Constants used by DEFINE_*
VBOOT_BASE='/usr/share/vboot'
DEFAULT_KEYS_FOLDER="$VBOOT_BASE/devkeys"
DEFAULT_PARTITIONS='2 4'

# Only store backup in stateful partition if available.
if [ -d /mnt/stateful_partition ]; then
  DEFAULT_BACKUP_FOLDER="/mnt/stateful_partition"
else
  DEFAULT_BACKUP_FOLDER="$(pwd)"
fi
DEFAULT_BACKUP_FOLDER="${DEFAULT_BACKUP_FOLDER}/cros_sign_backups"

# TODO(hungte) The default image selection is no longer a SSD, so the script
# works more like "make_dev_image".  We may change the file name in future.
ROOTDEV="$(rootdev -s 2>/dev/null)"
ROOTDEV_PARTITION="$(echo $ROOTDEV | sed -n 's/.*[^0-9]\([0-9][0-9]*\)$/\1/p')"
ROOTDEV_DISK="$(rootdev -s -d 2>/dev/null)"
ROOTDEV_KERNEL="$((ROOTDEV_PARTITION - 1))"

# DEFINE_string name default_value description flag
DEFINE_string image "$ROOTDEV_DISK" "Path to device or image file" "i"
DEFINE_string keys "$DEFAULT_KEYS_FOLDER" "Path to folder of dev keys" "k"
DEFINE_boolean remove_rootfs_verification \
  "${FLAGS_FALSE}" "Modify kernel boot config to disable rootfs verification" \
  "r"
DEFINE_boolean unlock_arch \
  "${FLAGS_FALSE}" "Unlock arch"
DEFINE_boolean lock_root \
  "${FLAGS_FALSE}" "lock rootfs"
DEFINE_boolean lock_arch \
  "${FLAGS_FALSE}" "lock arch"
DEFINE_boolean enable_earlycon "${FLAGS_FALSE}" \
  "Enable earlycon from stdout-path (ARM/ARM64) or SPCR (x86)." ""
DEFINE_boolean disable_earlycon "${FLAGS_FALSE}" \
  "Disable earlycon." ""
DEFINE_boolean enable_console "${FLAGS_FALSE}" \
  "Enable serial console." ""
DEFINE_boolean disable_console "${FLAGS_FALSE}" \
  "Disable serial console." ""
DEFINE_string backup_dir \
  "$DEFAULT_BACKUP_FOLDER" "Path of directory to store kernel backups" ""
DEFINE_string save_config "" \
  "Base filename to store kernel configs to, instead of resigning." ""
DEFINE_string set_config "" \
  "Base filename to load kernel configs from" ""
DEFINE_boolean edit_config "${FLAGS_FALSE}" \
  "Edit kernel config in-place." ""
DEFINE_string partitions "" \
  "List of partitions to examine (default: $DEFAULT_PARTITIONS)" ""
DEFINE_boolean recovery_key "$FLAGS_FALSE" \
  "Use recovery key to sign image (to boot from USB)" ""
DEFINE_boolean force "$FLAGS_FALSE" \
  "Skip validity checks and make the change" "f"
DEFINE_boolean default_rw_root "${FLAGS_TRUE}" \
  "When --remove_rootfs_verification is set, change root mount option to RW." ""
DEFINE_boolean no_resign_kernel "${FLAGS_FALSE}" \
  "make changes without resigning the kernel" ""
# Parse command line
FLAGS "$@" || exit 1
ORIGINAL_CMD="$0"
ORIGINAL_PARAMS="$@"
eval set -- "$FLAGS_ARGV"
ORIGINAL_PARTITIONS="$FLAGS_partitions"
: ${FLAGS_partitions:=$DEFAULT_PARTITIONS}

# Globals
# ----------------------------------------------------------------------------
set -e

# a log file to keep the output results of executed command
EXEC_LOG="$(make_temp_file)"

# Functions
# ----------------------------------------------------------------------------

# Removes rootfs verification from kernel boot parameter
# And strip out bootcache args if it exists
remove_rootfs_verification() {
  local new_root="PARTUUID=%U/PARTNROFF=1"
  # the first line in sed is to strip out bootcache details
  local rw_root_opt="s| ro | rw |"
  if [ "${FLAGS_default_rw_root}" = "${FLAGS_FALSE}" ]; then
    rw_root_opt="s| rw | ro |"
  fi

  echo "$*" | sed '
    s| dm=\"2 [^"]*bootcache[^"]* vroot | dm=\"1 vroot |
    s| root=/dev/dm-[0-9] | root='"$new_root"' |
    s| dm_verity.dev_wait=1 | dm_verity.dev_wait=0 |
    s| payload=PARTUUID=%U/PARTNROFF=1 | payload=ROOT_DEV |
    s| hashtree=PARTUUID=%U/PARTNROFF=1 | hashtree=HASH_DEV |
    '"${rw_root_opt}"
}

remove_legacy_boot_rootfs_verification() {
  # See src/scripts/create_legacy_bootloader_templates
  local image="$1"
  local mount_point="$(make_temp_dir)"
  local config_file
  debug_msg "Removing rootfs verification for legacy boot configuration."
  mount_image_partition "$image" 12 "$mount_point" || return $FLAGS_FALSE
  config_file="$mount_point/efi/boot/grub.cfg"
  [ ! -f "${config_file}" ] ||
    sudo sed -i -e 's/^ *defaultA=2 *$/defaultA=0/g' \
                -e 's/^ *defaultB=3 *$/defaultB=1/g' "${config_file}"
  config_file="$mount_point/syslinux/default.cfg"
  [ ! -f "$config_file" ] ||
    sudo sed -i 's/-vusb/-usb/g; s/-vhd/-hd/g' "$config_file"
  sudo umount "$mount_point"
}

# Enable/Disable earlycon or serial console
insert_parameter() {
  local cmdline="$1"
  local param="$2"

  if [ -n "${cmdline##*${param}*}" ]; then
    cmdline="${param} ${cmdline}"
  fi

  echo "${cmdline}"
}

remove_parameter() {
  local cmdline="$1"
  local param="$2"

  cmdline=$(echo "${cmdline}" | sed '
    s/'"${param} "'//g')

  echo "${cmdline}"
}

# Wrapped version of dd
mydd() {
  # oflag=sync is safer, but since we need bs=512, syncing every block would be
  # very slow.
  dd "$@" >"$EXEC_LOG" 2>&1 ||
    die "Failed in [dd $*], Message: $(cat "${EXEC_LOG}")"
}

# Prints a more friendly name from kernel index number
cros_kernel_name() {
  case $1 in
    2)
      echo "Kernel A"
      ;;
    4)
      echo "Kernel B"
      ;;
    6)
      echo "Kernel C"
      ;;
    *)
      echo "Partition $1"
  esac
}

find_valid_kernel_partitions() {
  local part_id
  local valid_partitions=""
  for part_id in $*; do
    local name="$(cros_kernel_name $part_id)"
    local kernel_part="$(make_partition_dev "$FLAGS_image" "$part_id")"
    info "futil: $FUTILITY"
    if [ -z "$(${FUTILITY} dump_kernel_config "$kernel_part" 2>"$EXEC_LOG")" ]; then
      info "${name}: no kernel boot information, ignored." >&2
    else
      [ -z "$valid_partitions" ] &&
        valid_partitions="$part_id" ||
        valid_partitions="$valid_partitions $part_id"
      continue
    fi
  done
  debug_msg "find_valid_kernel_partitions: [$*] -> [$valid_partitions]"
  echo "$valid_partitions"
}

# Resigns a kernel on SSD or image.
resign_ssd_kernel() {
  local ssd_device="$1"
  local bs="$(blocksize "${ssd_device}")"

  # reasonable size for current kernel partition
  local min_kernel_size=$((8000 * 1024 / bs))
  local resigned_kernels=0

  for kernel_index in $FLAGS_partitions; do
    local old_blob="$(make_temp_file)"
    local new_blob="$(make_temp_file)"
    local name="$(cros_kernel_name $kernel_index)"
    local rootfs_index="$(($kernel_index + 1))"

    debug_msg "Probing $name information"
    local offset size
    offset="$(partoffset "$ssd_device" "$kernel_index")" ||
      die "Failed to get partition ${kernel_index} offset from ${ssd_device}"
    size="$(partsize "$ssd_device" "$kernel_index")" ||
      die "Failed to get partition ${kernel_index} size from ${ssd_device}"
    if [ ! $size -gt $min_kernel_size ]; then
      info "${name} seems too small (${size}), ignored."
      continue
    fi

    debug_msg "Reading $name from partition $kernel_index"
    mydd if="$ssd_device" of="$old_blob" bs=$bs skip=$offset count=$size

    debug_msg "Checking if $name is valid"

    local kernel_config
    if ! kernel_config="$(${FUTILITY} dump_kernel_config "$old_blob" 2>"$EXEC_LOG")"; then
      debug_msg "dump_kernel_config error message: $(cat "$EXEC_LOG")"
      info "${name}: no kernel boot information, ignored."
      continue
    fi


  if [ "$FLAGS_no_resign_kernel" = "$FLAGS_TRUE" ]; then
    info "Skipping resign for ${FLAGS_image}"
 if [ ${FLAGS_remove_rootfs_verification} = $FLAGS_TRUE ]; then
      local root_offset_sector=$(partoffset "$ssd_device" $rootfs_index)
      local root_offset_bytes=$((root_offset_sector * bs))
      info "dev: ${ssd_device} $root_offset_bytes"
      if ! is_ext2 "$ssd_device" "$root_offset_bytes"; then
        debug_msg "Non-ext2 partition: $ssd_device$rootfs_index, skip."
      elif ! rw_mount_disabled "$ssd_device" "$root_offset_bytes"; then
        debug_msg "Root file system is writable. No need to modify."
      else
        # disable the RO ext2 hack
        info "Disabling rootfs ext2 RO bit hack"
        enable_rw_mount "$ssd_device" "$root_offset_bytes" >"$EXEC_LOG" 2>&1 ||
          die "Failed turning off rootfs RO bit. OS may be corrupted. " \
              "Message: $(cat "${EXEC_LOG}")"
      fi
    fi
    return
  fi

    if [ -n "${FLAGS_save_config}" ]; then
      # Save current kernel config
      local old_config_file
      old_config_file="${FLAGS_save_config}.$kernel_index"
      info "Saving ${name} config to ${old_config_file}"
      echo "$kernel_config" > "$old_config_file"
      # Just save; don't resign
      continue
    fi

    if [ -n "${FLAGS_set_config}" ]; then
      # Set new kernel config from file
      local new_config_file
      new_config_file="${FLAGS_set_config}.$kernel_index"
      kernel_config="$(cat "$new_config_file")" ||
        die "Failed to read new kernel config from ${new_config_file}"
      debug_msg "New kernel config: $kernel_config)"
      info "${name}: Replaced config from ${new_config_file}"
    fi

    if [ "${FLAGS_edit_config}" = ${FLAGS_TRUE} ]; then
      debug_msg "Editing kernel config file."
      local new_config_file="$(make_temp_file)"
      echo "${kernel_config}" >"${new_config_file}"
      local old_md5sum="$(md5sum "${new_config_file}")"
      local editor="${VISUAL:-${EDITOR:-vi}}"
      info "${name}: Editing kernel config:"
      # On ChromiumOS, some builds may come with broken EDITOR that refers to
      # nano so we want to check again if the editor really exists.
      if type "${editor}" >/dev/null 2>&1; then
        "${editor}" "${new_config_file}"
      else
        # This script runs under dash but we want readline in bash to support
        # editing in in console.
        bash -c "read -e -i '${kernel_config}' &&
                 echo \"\${REPLY}\" >${new_config_file}" ||
          die "Failed to run editor. Please specify editor name by VISUAL."
      fi
      kernel_config="$(cat "${new_config_file}")"
      if [ "$(md5sum "${new_config_file}")" = "${old_md5sum}" ]; then
        info "${name}: Config not changed."
      else
        debug_msg "New kernel config: ${kernel_config})"
        info "${name}: Config updated"
      fi
    fi

    if [ ${FLAGS_remove_rootfs_verification} = $FLAGS_FALSE ]; then
      debug_msg "Bypassing rootfs verification check"
    else
      debug_msg "Changing boot parameter to remove rootfs verification"
      kernel_config="$(remove_rootfs_verification "$kernel_config")"
      debug_msg "New kernel config: $kernel_config"
      info "${name}: Disabled rootfs verification."
      remove_legacy_boot_rootfs_verification "$ssd_device"
    fi

    if [ "${FLAGS_enable_earlycon}" = "${FLAGS_TRUE}" ]; then
      debug_msg "Enabling earlycon"
      kernel_config="$(insert_parameter "${kernel_config}" "earlycon")"
      debug_msg "New kernel config: ${kernel_config}"
    elif [ "${FLAGS_disable_earlycon}" = "${FLAGS_TRUE}" ]; then
      debug_msg "Disabling earlycon"
      kernel_config="$(remove_parameter "${kernel_config}" "earlycon")"
      debug_msg "New kernel config: ${kernel_config}"
    fi

    if [ "${FLAGS_enable_console}" = "${FLAGS_TRUE}" ]; then
      debug_msg "Enabling serial console"
      kernel_config="$(remove_parameter "${kernel_config}" "console=")"
      debug_msg "New kernel config: ${kernel_config}"
    elif [ "${FLAGS_disable_console}" = "${FLAGS_TRUE}" ]; then
      debug_msg "Disabling serial console"
      kernel_config="$(insert_parameter "${kernel_config}" "console=")"
      debug_msg "New kernel config: ${kernel_config}"
    fi

    local new_kernel_config_file="$(make_temp_file)"
    echo -n "$kernel_config"  >"$new_kernel_config_file"




    debug_msg "Re-signing $name from $old_blob to $new_blob"
    debug_msg "Using key: $KERNEL_DATAKEY"
    vbutil_kernel \
      --repack "$new_blob" \
      --keyblock "$KERNEL_KEYBLOCK" \
      --config "$new_kernel_config_file" \
      --signprivate "$KERNEL_DATAKEY" \
      --oldblob "$old_blob" >"$EXEC_LOG" 2>&1 ||
      die "Failed to resign ${name}. Message: $(cat "${EXEC_LOG}")"

    debug_msg "Creating new kernel image (vboot+code+config)"
    local new_kern="$(make_temp_file)"
    cp "$old_blob" "$new_kern"
    mydd if="$new_blob" of="$new_kern" conv=notrunc

    if is_debug_mode; then
      debug_msg "for debug purposes, check *.dbgbin"
      cp "$old_blob" old_blob.dbgbin
      cp "$new_blob" new_blob.dbgbin
      cp "$new_kern" new_kern.dbgbin
    fi

    debug_msg "Verifying new kernel and keys"
    vbutil_kernel \
      --verify "$new_kern" \
      --signpubkey "$KERNEL_PUBKEY" --verbose >"$EXEC_LOG" 2>&1 ||
      die "Failed to verify new ${name}. Message: $(cat "${EXEC_LOG}")"

    debug_msg "Backup old kernel blob"
    local backup_date_time="$(date +'%Y%m%d_%H%M%S')"
    local backup_name="$(echo "$name" | sed 's/ /_/g; s/^K/k/')"
    local backup_file_name="${backup_name}_${backup_date_time}.bin"
    local backup_file_path="$FLAGS_backup_dir/$backup_file_name"
    if mkdir -p "$FLAGS_backup_dir" &&
      cp -f "$old_blob" "$backup_file_path"; then
      info "Backup of ${name} is stored in: ${backup_file_path}"
    else
      warn "Cannot create file in ${FLAGS_backup_dir} ... Ignore backups."
    fi

    debug_msg "Writing $name to partition $kernel_index"
    mydd \
      if="$new_kern" \
      of="$ssd_device" \
      seek=$offset \
      bs=$bs \
      count=$size \
      conv=notrunc
    resigned_kernels=$(($resigned_kernels + 1))

    debug_msg "Make the root file system writable if needed."
    # TODO(hungte) for safety concern, a more robust way would be to:
    # (1) change kernel config to ro
    # (2) check if we can enable rw mount
    # (3) change kernel config to rw

    if [ ${FLAGS_lock_root} = $FLAGS_TRUE ]; then
      local root_offset_sector=$(partoffset "$ssd_device" $rootfs_index)
      local root_offset_bytes=$((root_offset_sector * bs))
      # enable the RO ext2 hack
      if ! is_ext2 "$ssd_device" "$root_offset_bytes"; then
        debug_msg "Non-ext2 partition: $ssd_device$rootfs_index, skip."
      else
        echo "Re-enabling the ext2 hack :trolley:"
        disable_rw_mount "$ssd_device" "$root_offset_bytes" >"$EXEC_LOG" 2>&1 ||
          die "Failed turning off rootfs RO bit. OS may be corrupted. " \
            "Message: $(cat "${EXEC_LOG}")"
      fi
    fi
    if [ ${FLAGS_lock_arch} = $FLAGS_TRUE ]; then
      local root_offset_sector=$(partoffset "$ssd_device" 13)
      local root_offset_bytes=$((root_offset_sector * bs))
      # enable the RO ext2 hack
      if ! is_ext2 "$ssd_device" "$root_offset_bytes"; then
        debug_msg "Non-ext2 partition: $ssd_device$rootfs_index, skip."
      else
        echo "Locking arch partition"
        disable_rw_mount "$ssd_device" "$root_offset_bytes" >"$EXEC_LOG" 2>&1 ||
          die "Failed turning off rootfs RO bit. OS may be corrupted. " \
            "Message: $(cat "${EXEC_LOG}")"
      fi
    fi
    if [ ${FLAGS_unlock_arch} = $FLAGS_TRUE ]; then
      local root_offset_sector=$(partoffset "$ssd_device" 13)
      local root_offset_bytes=$((root_offset_sector * bs))
      # enable the RO ext2 hack
      if ! is_ext2 "$ssd_device" "$root_offset_bytes"; then
        echo "Non-ext2 partition: $ssd_device$rootfs_index, skip."
      else
        echo "unlocking arch partition"
        enable_rw_mount "$ssd_device" "$root_offset_bytes" >"$EXEC_LOG" 2>&1 ||
          die "Failed turning off rootfs RO bit. OS may be corrupted. " \
            "Message: $(cat "${EXEC_LOG}")"
      fi
    fi

    if [ ${FLAGS_remove_rootfs_verification} = $FLAGS_TRUE ]; then
      local root_offset_sector=$(partoffset "$ssd_device" $rootfs_index)
      local root_offset_bytes=$((root_offset_sector * bs))
      if ! is_ext2 "$ssd_device" "$root_offset_bytes"; then
        debug_msg "Non-ext2 partition: $ssd_device$rootfs_index, skip."
      elif ! rw_mount_disabled "$ssd_device" "$root_offset_bytes"; then
        debug_msg "Root file system is writable. No need to modify."
      else
        # disable the RO ext2 hack
        info "Disabling rootfs ext2 RO bit hack"
        enable_rw_mount "$ssd_device" "$root_offset_bytes" >"$EXEC_LOG" 2>&1 ||
          die "Failed turning off rootfs RO bit. OS may be corrupted. " \
              "Message: $(cat "${EXEC_LOG}")"
      fi
    fi

    # Sometimes doing "dump_kernel_config" or other I/O now (or after return to
    # shell) will get the data before modification. Not a problem now, but for
    # safety, let's try to sync more.
    sync; sync; sync

    info "${name}: Re-signed with developer keys successfully."
  done

  # If we saved the kernel config, exit now so we don't print an error
  if [ -n "${FLAGS_save_config}" ]; then
    info "(Kernels have not been resigned.)"
    exit 0
  fi

  return $resigned_kernels
}

validity_check_crossystem_flags() {
  debug_msg "crossystem validity check"
  if [ -n "${FLAGS_save_config}" ]; then
    debug_msg "not resigning kernel."
    return
  fi

  if [ "$(crossystem dev_boot_signed_only)" = "0" ]; then
    debug_msg "dev_boot_signed_only not set - safe."
    return
  fi

  echo "
  ERROR: YOUR FIRMWARE WILL ONLY BOOT SIGNED IMAGES.

  Modifying the kernel or root filesystem will result in an unusable system.  If
  you really want to make this change, allow the firmware to boot self-signed
  images by running:

    sudo crossystem dev_boot_signed_only=0

  before re-executing this command.
  "
  return $FLAGS_FALSE
}

validity_check_live_partitions() {
  debug_msg "Partition validity check"
  if [ "$FLAGS_partitions" = "$ROOTDEV_KERNEL" ]; then
    debug_msg "only for current active partition - safe."
    return
  fi
  if [ "$ORIGINAL_PARTITIONS" != "" ]; then
    debug_msg "user has assigned partitions - provide more info."
    info "Making change to ${FLAGS_partitions} on ${FLAGS_image}."
    return
  fi
  echo "
  ERROR: YOU ARE TRYING TO MODIFY THE LIVE SYSTEM IMAGE $FLAGS_image.

  The system may become unusable after that change, especially when you have
  some auto updates in progress. To make it safer, we suggest you to only
  change the partition you have booted with. To do that, re-execute this command
  as:

    sudo $ORIGINAL_CMD $ORIGINAL_PARAMS --partitions $ROOTDEV_KERNEL

  If you are sure to modify other partition, please invoke the command again and
  explicitly assign only one target partition for each time  (--partitions N )
  "
  return $FLAGS_FALSE
}

validity_check_live_firmware() {
  debug_msg "Firmware compatibility validity check"
  if [ "$(crossystem mainfw_type)" = "developer" ]; then
    debug_msg "developer type firmware in active."
    return
  fi
  debug_msg "Loading firmware to check root key..."
  local bios_image="$(make_temp_file)"
  local rootkey_file="$(make_temp_file)"
  info "checking system firmware..."
  sudo flashrom -p host -i GBB -r "$bios_image" >/dev/null 2>&1
  futility gbb -g --rootkey="$rootkey_file" "$bios_image" >/dev/null 2>&1
  if [ ! -s "$rootkey_file" ]; then
    debug_msg "failed to read root key from system firmware..."
  else
    # The magic 130 is counted by "od dev-rootkey" for the lines until the body
    # of key is reached. Trailing bytes (0x00 or 0xFF - both may appear, and
    # that's why we need to skip them) are started at line 131.
    # TODO(hungte) compare with rootkey in $VBOOT_BASE directly.
    local rootkey_hash="$(od "$rootkey_file" |
                          head -130 | md5sum |
                          sed 's/ .*$//' )"
    if [ "$rootkey_hash" = "a13642246ef93daaf75bd791446fec9b" ]; then
      debug_msg "detected DEV root key in firmware."
      return
    else
      debug_msg "non-devkey hash: $rootkey_hash"
    fi
  fi

  echo "
  ERROR: YOU ARE NOT USING DEVELOPER FIRMWARE, AND RUNNING THIS COMMAND MAY
  THROW YOUR CHROMEOS DEVICE INTO UN-BOOTABLE STATE.

  You need to either install developer firmware, or change system root key.

   - To install developer firmware: type command
     sudo chromeos-firmwareupdate --mode=todev

   - To change system rootkey: disable firmware write protection (a hardware
     switch) and then type command:
     sudo $SCRIPT_BASE/make_dev_firmware.sh

  If you are sure that you want to make such image without developer
  firmware or you've already changed system root keys, please run this
  command again with --force paramemeter:

     sudo $ORIGINAL_CMD --force $ORIGINAL_PARAMS
  "
  return $FLAGS_FALSE
}

validity_check() {
  validity_check_live_partitions || return $FLAGS_FALSE

  # Remaining checks depend on firmware; skip if device is running in a VM.
  if crossystem 'inside_vm?1'; then
    debug_msg "Device is a VM, skipping firmware checks"
    return $FLAGS_TRUE
  fi

  validity_check_live_firmware || return $FLAGS_FALSE
  validity_check_crossystem_flags || return $FLAGS_FALSE
  return $FLAGS_TRUE
}

# Main
# ----------------------------------------------------------------------------
main() {
  local num_signed=0
  local num_given=$(echo "$FLAGS_partitions" | wc -w)
  local kaltdir=$(dirname $0)/keys
  if [ -d "$kaltdir" ]; then
   FLAGS_keys=$kaltdir
  fi
  # Check parameters
  if [ "$FLAGS_recovery_key" = "$FLAGS_TRUE" ]; then
    KERNEL_KEYBLOCK="$FLAGS_keys/recovery_kernel.keyblock"
    KERNEL_DATAKEY="$FLAGS_keys/recovery_kernel_data_key.vbprivk"
    KERNEL_PUBKEY="$FLAGS_keys/recovery_key.vbpubk"
  else
    KERNEL_KEYBLOCK="$FLAGS_keys/kernel.keyblock"
    KERNEL_DATAKEY="$FLAGS_keys/kernel_data_key.vbprivk"
    KERNEL_PUBKEY="$FLAGS_keys/kernel_subkey.vbpubk"
  fi

  debug_msg "Prerequisite check"
  ensure_files_exist \
    "$KERNEL_KEYBLOCK" \
    "$KERNEL_DATAKEY" \
    "$KERNEL_PUBKEY" \
    "$FLAGS_image" ||
    exit 1

  # checks for running on a live system image.
  if [ "$FLAGS_image" = "$ROOTDEV_DISK" ]; then
    debug_msg "check valid kernel partitions for live system"
    local valid_partitions="$(find_valid_kernel_partitions $FLAGS_partitions)"
    [ -n "$valid_partitions" ] ||
      die "No valid kernel partitions on ${FLAGS_image} (${FLAGS_partitions})."
    FLAGS_partitions="$valid_partitions"

    # Validity checks
    if [ "$FLAGS_force" = "$FLAGS_TRUE" ]; then
      echo "
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      ! INFO: ALL VALIDITY CHECKS WERE BYPASSED. YOU ARE ON YOUR OWN. !
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      " >&2
      local i
      for i in $(seq 5 -1 1); do
        echo -n "\rStart in $i second(s) (^C to abort)...  " >&2
        sleep 1
      done
      echo ""
    elif ! validity_check; then
      die "IMAGE ${FLAGS_image} IS NOT MODIFIED."
    fi
  fi

    resign_ssd_kernel "$FLAGS_image" || num_signed=$?

    debug_msg "Complete."
    if [ $num_signed -gt 0 -a $num_signed -le $num_given ]; then
    # signed something at least
      info "Successfully re-signed ${num_signed} of ${num_given} kernel(s)" \
      " on device ${FLAGS_image}."
      info "Please remember to reboot before updating the kernel on this device."
    else
  if [ "$FLAGS_no_resign_kernel" = "$FLAGS_FALSE" ]; then
      die "Failed re-signing kernels."
  fi
    fi
}

# People using this to process images may forget to add "-i",
# so adding parameter check is safer.
if [ "$#" -gt 0 ]; then
  flags_help
  die "Unknown parameters: $*"
fi

main