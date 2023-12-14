#!/bin/bash

#build the bootloader image

set -e
if [ "$DEBUG" ]; then
  set -x
fi

. ./patch_initramfs.sh
. ./build_image.sh

print_help() {
  echo "Usage: ./build.sh output_path shim_path rootfs_dir"
}

check_deps() {
  local needed_commands="cpio binwalk pcregrep realpath cgpt mkfs.ext4 mkfs.ext2 fdisk rsync"
  for command in $needed_commands; do
    if ! command -v $command &> /dev/null; then
      echo $command
    fi
  done
}

if [ "$EUID" -ne 0 ]; then
  echo "this needs to be run as root."
  exit 1
fi

if [ -z "$3" ]; then
  print_help
  exit 1
fi

missing_commands=$(check_deps)
if [ "${missing_commands}" ]; then
  echo "You are missing dependencies needed for this script."
  echo "Commands needed:"
  echo "${missing_commands}"
  exit 1
fi

output_path=$(realpath "${1}")
shim_path=$(realpath "${2}")
rootfs_dir=$(realpath "${3}")

echo "created loop device for shim"
shim_loop=$(create_loop "${shim_path}")
kernel_loop="${shim_loop}p2" #KERN-A should always be p2

echo "copying shim kernel to new file in /tmp"
kernel_dir=/tmp/shim_kernel
mkdir $kernel_dir -p
dd if=$kernel_loop of=$kernel_dir/kernel.bin bs=1M status=none

echo "extracting data from kernel"
previous_dir=$(pwd)
cd $kernel_dir
if [ -e "${kernel_dir}/binwalk.out" ]; then
  #don't run binwalk again if we don't need to
  binwalk_out=$(cat $kernel_dir/binwalk.out)
else
  binwalk_out=$(binwalk --extract kernel.bin --run-as=root)
  echo $binwalk_out > $kernel_dir/binwalk.out
fi
#i can't be bothered to learn how to use sed
extracted_file=$(echo $binwalk_out | pcregrep -o1 "\d+\s+0x([0-9A-F]+)\s+gzip compressed data")

echo "extracting initramfs archive from kernel (this may take a while)"
cd _kernel.bin.extracted/
if [ ! -e "_${extracted_file}.extracted/" ]; then
  binwalk --extract $extracted_file --run-as=root > /dev/null
fi
cd "_${extracted_file}.extracted/"
cpio_file=$(file ./* | pcregrep -o1 "([0-9A-F]+):\s+ASCII cpio archive")

echo "extracting initramfs cpio archive"
initramfs_dir=/tmp/shim_initramfs
rm -rf $initramfs_dir
cat $cpio_file | cpio -D $initramfs_dir -imd --quiet
echo "shim initramfs extracted to ${initramfs_dir}"

#leave /tmp
cd $previous_dir

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

echo "mounting the original shim rootfs"
shim_rootfs="/tmp/shim_rootfs"
make_mountable "${shim_loop}p3"
safe_mount "${shim_loop}p3" $shim_rootfs

echo "copying data into the image"
populate_partitions $image_loop $initramfs_dir $rootfs_dir

echo "cleaning up loop devices"
losetup -d $shim_loop
losetup -d $image_loop
echo "done"