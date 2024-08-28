#!/bin/bash

create_loop() {
  local loop_device=$(losetup -f)
  if [ ! -b "$loop_device" ]; then
    #we might run out of loop devices, see https://stackoverflow.com/a/66020349
    local major=$(grep loop /proc/devices | cut -c3)
    local number="$(echo "$loop_device" | grep -Eo '[0-9]+' | tail -n1)"
    mknod $loop_device b $major $number
  fi
  losetup -P $loop_device "${1}"
  echo $loop_device
}

#set required flags on the kernel partition
make_bootable() {
  cgpt add -i 2 -S 1 -T 5 -P 10 -l kernel $1
}

partition_disk() {
  local image_path=$(realpath -m "${1}")
  local bootloader_size="$2"
  local rootfs_name="$3"

  #create partition table with fdisk
  ( 
    echo g #new gpt disk label

    #create 1MB stateful
    echo n #new partition
    echo #accept default parition number
    echo #accept default first sector
    echo +1M #partition size is 1M

    #create 32MB kernel partition
    echo n
    echo #accept default parition number
    echo #accept default first sector
    echo +32M #partition size is 32M
    echo t #change partition type
    echo #accept default parition number
    echo FE3A2A5D-4F32-41A7-B725-ACCC3285A309 #chromeos kernel type

    #create bootloader partition
    echo n
    echo #accept default parition number
    echo #accept default first sector
    echo "+${bootloader_size}M" #set partition size
    echo t #change partition type
    echo #accept default parition number
    echo 3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC #chromeos rootfs type

    #create rootfs partition
    echo n
    echo #accept default parition number
    echo #accept default first sector
    echo #accept default size to fill rest of image
    echo x #enter expert mode
    echo n #change the partition name
    echo #accept default partition number
    echo "shimboot_rootfs:$rootfs_name" #set partition name
    echo r #return to normal more

    #write changes
    echo w
  ) | fdisk $image_path > /dev/null
}

safe_mount() {
  local source="$1"
  local dest="$2"
  local opts="$3"
  
  umount $dest 2> /dev/null || /bin/true
  rm -rf $dest
  mkdir -p $dest
  if [ "$opts" ]; then
    mount $source $dest -o $opts
  else
    mount $source $dest
  fi
}

create_partitions() {
  local image_loop=$(realpath -m "${1}")
  local kernel_path=$(realpath -m "${2}")

  #create stateful
  mkfs.ext4 "${image_loop}p1"
  #copy kernel
  dd if=$kernel_path of="${image_loop}p2" bs=1M oflag=sync
  make_bootable $image_loop
  #create bootloader partition
  mkfs.ext2 "${image_loop}p3"
  #create rootfs partition
  mkfs.ext4 "${image_loop}p4"
}

populate_partitions() {
  local image_loop=$(realpath -m "${1}")
  local bootloader_dir=$(realpath -m "${2}")
  local rootfs_dir=$(realpath -m "${3}")
  local quiet="$4"

  #figure out if we are on a stable release
  local git_tag="$(git tag -l --contains HEAD)"

  #mount and write empty file to stateful
  local stateful_mount=/tmp/shim_stateful
  safe_mount "${image_loop}p1" $stateful_mount
  mkdir -p $stateful_mount/dev_image/etc/
  mkdir -p $stateful_mount/dev_image/factory/sh
  touch $stateful_mount/dev_image/etc/lsb-factory
  umount $stateful_mount

  #mount and write to bootloader rootfs
  local bootloader_mount="/tmp/shim_bootloader"
  safe_mount "${image_loop}p3" "$bootloader_mount"
  cp -r $bootloader_dir/* "$bootloader_mount"
  if [ ! "$git_tag" ]; then #mark it as a dev version if needed
    touch "$bootloader_mount/opt/.shimboot_version_dev"
  fi
  umount "$bootloader_mount"

  #write rootfs to image
  local rootfs_mount=/tmp/new_rootfs
  safe_mount "${image_loop}p4" $rootfs_mount
  if [ "$quiet" ]; then
    cp -ar $rootfs_dir/* $rootfs_mount
  else
    copy_progress $rootfs_dir $rootfs_mount
  fi
  umount $rootfs_mount
}

create_image() {
  local image_path=$(realpath -m "${1}")
  local bootloader_size="$2"
  local rootfs_size="$3"
  local rootfs_name="$4"
  
  #stateful + kernel + bootloader + rootfs
  local total_size=$((1 + 32 + $bootloader_size + $rootfs_size))
  rm -rf "${image_path}"
  fallocate -l "${total_size}M" "${image_path}"

  partition_disk $image_path $bootloader_size $rootfs_name
}

patch_initramfs() {
  local initramfs_path=$(realpath -m $1)

  rm "${initramfs_path}/init" -f
  cp -r bootloader/* "${initramfs_path}/"

  find ${initramfs_path}/bin -name "*" -exec chmod +x {} \;
}

#clean up unused loop devices
clean_loops() {
  local loop_devices="$(losetup -a | awk -F':' {'print $1'})"
  for loop_device in $loop_devices; do
    local mountpoints="$(cat /proc/mounts | grep "$loop_device")"
    if [ ! "$mountpoints" ]; then
      losetup -d $loop_device
    fi
  done
}

copy_progress() {
  local source="$1"
  local destination="$2"
  local total_bytes="$(du -sb "$source" | cut -f1)"
  mkdir -p "$destination"
  tar -cf - -C "${source}" . | pv -f -s $total_bytes | tar -xf - -C "${destination}"
}
