#!/bin/bash

#build the bootloader image

set -e
if [ "$DEBUG" ]; then
  set -x
fi

. ./image_utils.sh
. ./shim_utils.sh

print_help() {
  echo "Usage: ./build.sh output_path shim_path rootfs_dir"
}

if [ "$EUID" -ne 0 ]; then
  echo "this needs to be run as root."
  exit 1
fi

if [ -z "$3" ]; then
  print_help
  exit 1
fi

. ./common.sh
assert_deps "cpio binwalk pcregrep realpath cgpt mkfs.ext4 mkfs.ext2 fdisk rsync"

output_path=$(realpath -m "${1}")
shim_path=$(realpath -m "${2}")
rootfs_dir=$(realpath -m "${3}")

echo "created loop device for shim"
shim_loop=$(create_loop "${shim_path}")
kernel_loop="${shim_loop}p2" #KERN-A should always be p2

echo "copying shim kernel to new file in /tmp"
kernel_dir=/tmp/shim_kernel
mkdir $kernel_dir -p
dd if=$kernel_loop of=$kernel_dir/kernel.bin bs=1M status=none

echo "extracting data from kernel"
initramfs_dir=/tmp/shim_initramfs
rm -rf $initramfs_dir
extract_initramfs $kernel_dir/kernel.bin $kernel_dir $initramfs_dir
losetup -d $shim_loop

echo "patching initramfs"
patch_initramfs $initramfs_dir

echo "creating disk image"
rootfs_size=$(du -sm $rootfs_dir | cut -f 1)
rootfs_part_size=$(($rootfs_size * 12 / 10))
#create a 20mb bootloader partition
#rootfs partition is 20% larger than its contents
create_image $output_path 20 $rootfs_part_size

echo "creating loop device for the image"
image_loop=$(create_loop ${output_path})

echo "creating partitions on the disk image"
create_partitions $image_loop "${kernel_dir}/kernel.bin"

echo "copying data into the image"
populate_partitions $image_loop $initramfs_dir $rootfs_dir

echo "cleaning up loop devices"
losetup -d $image_loop
echo "done"