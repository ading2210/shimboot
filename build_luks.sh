#!/bin/bash

#build the bootloader image
#Modified by ERROR 404: NULL NOT FOUND to add LUKS2 support

. ./common.sh
. ./image_utils.sh
. ./shim_utils.sh

print_help() {
  echo "Usage: ./build.sh output_path shim_path rootfs_dir"
  echo "Valid named arguments (specify with 'key=value'):"
  echo "  quiet - Don't use progress indicators which may clog up log files."
  echo "  arch  - Set this to 'arm64' to specify that the shim is for an ARM chromebook."
}

stage() {
  echo -e "[ \e[1m\x1b[32m$1\x1b[0m\e[0m ]"
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
  echo "${PASSWD}" | ./$CRYPTSETUP_PATH luksFormat "${image_loop}p4"
  echo "${PASSWD}" | ./$CRYPTSETUP_PATH luksOpen "${image_loop}p4" rootfs
  mkfs.ext4 /dev/mapper/rootfs
}

populate_partitions() {
  local image_loop=$(realpath -m "${1}")
  local bootloader_dir=$(realpath -m "${2}")
  local rootfs_dir=$(realpath -m "${3}")
  local quiet="$4"

  #mount and write empty file to stateful
  local stateful_mount=/tmp/shim_stateful
  safe_mount "${image_loop}p1" $stateful_mount
  mkdir -p $stateful_mount/dev_image/etc/
  mkdir -p $stateful_mount/dev_image/factory/sh
  touch $stateful_mount/dev_image/etc/lsb-factory
  umount $stateful_mount

  #mount and write to bootloader rootfs
  local bootloader_mount=/tmp/shim_bootloader
  safe_mount "${image_loop}p3" $bootloader_mount
  cp -r $bootloader_dir/* $bootloader_mount
  umount $bootloader_mount

  #write rootfs to image
  local rootfs_mount=/tmp/new_rootfs
  safe_mount /dev/mapper/rootfs $rootfs_mount
  if [ "$quiet" ]; then
    cp -ar $rootfs_dir/* $rootfs_mount
  else
    copy_progress $rootfs_dir $rootfs_mount
  fi
  cp $CRYPTSETUP_PATH $rootfs_mount/bin/cryptsetup
  umount $rootfs_mount
  ./$CRYPTSETUP_PATH close rootfs
}


assert_root
assert_deps "cpio binwalk pcregrep realpath cgpt mkfs.ext4 mkfs.ext2 fdisk lz4 pv"
assert_args "$3"
parse_args "$@"

output_path=$(realpath -m "${1}")
shim_path=$(realpath -m "${2}")
rootfs_dir=$(realpath -m "${3}")
if [ "${args['arch']}" ]; then
  CRYPTSETUP_PATH=cryptsetup_arm64
else
  CRYPTSETUP_PATH=cryptsetup_x86_64
fi

printf "Enter the LUKS2 password for the image: "
read PASSWD

if [ ! -f $CRYPTSETUP_PATH ]; then
  stage "downloading cryptsetup binary"
  curl -LO "https://github.com/FWSmasher/CryptoSmite/raw/main/${CRYPTSETUP_PATH}"
  chmod +x $CRYPTSETUP_PATH
fi

stage "reading the shim image"
initramfs_dir=/tmp/shim_initramfs
kernel_img=/tmp/kernel.img
rm -rf $initramfs_dir $kernel_img
extract_initramfs_full $shim_path $initramfs_dir $kernel_img "${args['arch']}"

stage "patching initramfs"
patch_initramfs $initramfs_dir

stage "creating disk image"
rootfs_size=$(du -sm $rootfs_dir | cut -f 1)
rootfs_part_size=$(($rootfs_size * 12 / 10 + 5))
#create a 20mb bootloader partition
#rootfs partition is 20% larger than its contents
create_image $output_path 20 $rootfs_part_size

stage "creating loop device for the image"
image_loop=$(create_loop ${output_path})

stage "creating partitions on the disk image"
create_partitions $image_loop $kernel_img

stage "copying data into the image"
populate_partitions $image_loop $initramfs_dir $rootfs_dir "${args['quiet']}"
rm -rf $initramfs_dir $kernel_img

stage "cleaning up loop devices"
losetup -d $image_loop
echo "done"
