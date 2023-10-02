#!/bin/bash

#build the bootloader image

set -e
if [ "$DEBUG" ]; then
  set -x
fi

print_help() {
  echo "Usage: ./build.sh path_to_shim"
}

create_loop() {
  local loop_device=$(losetup -f)
  losetup -P $loop_device $1
  echo $loop_device
}

if [ "$EUID" -ne 0 ]; then
  echo "this needs to be run as root."
  exit 1
fi

if [ -z "$1" ]; then
  print_help
  exit 1
fi

shim_path=$(realpath $1)

echo "created loop device for shim"
shim_loop=$(create_loop $shim_path)
kernel_loop="${shim_loop}p2" #KERN-A should always be p2

echo "copying shim kernel to new file in /tmp"
kernel_dir=/tmp/shim_kernel
rm -rf $kernel_dir
mkdir $kernel_dir -p
dd if=$kernel_loop of=$kernel_dir/kernel.bin bs=1M status=none

echo "extracting data from kernel"
previous_dir=$(pwd)
cd $kernel_dir
binwalk_out=$(binwalk --extract kernel.bin --run-as=root)
#i can't be bothered to learn how to use sed
extracted_file=$(echo $binwalk_out | pcregrep -o1 "\d+\s+0x([0-9A-F]+)\s+gzip compressed data")

echo "extracting initramfs archive from kernel"
cd _kernel.bin.extracted/
binwalk --extract $extracted_file --run-as=root > /dev/null
cd "_${extracted_file}.extracted/"
cpio_file=$(file ./* | pcregrep -o1 "([0-9A-F]+):\s+ASCII cpio archive")

echo "extracting initramfs cpio archive"
initramfs_dir=/tmp/shim_initramfs
rm -rf $initramfs_dir
cat $cpio_file | cpio -D $initramfs_dir -imd --quiet

echo "shim initramfs extracted to ${initramfs_dir}"

cd $previous_dir

echo "cleaning up loop devices"
losetup -d $shim_loop