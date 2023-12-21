#!/bin/bash

#build a rootfs that uses a squashfs + unionfs
#consists of a minimal busybox system containing:
# - FUSE kernel modules from the shim
# - unionfs-fuse statically compiled 
# - the main squashfs, compressed with gzip
#this script is currently incomplete

set -e
if [ "$DEBUG" ]; then
  set -x
fi

. ./image_utils.sh
. ./shim_utils.sh

print_help() {
  echo "Usage: ./build_squashfs.sh rootfs_dir uncompressed_rootfs_dir path_to_shim"
}

if [ "$EUID" -ne 0 ]; then
  echo "this needs to be run as root."
  exit 1
fi

if [ -z "$3" ]; then
  print_help
  exit 1
fi

compile_unionfs() {
  local out_path="$1"
  local working_path="$2"

  local repo_url="https://github.com/rpodgorny/unionfs-fuse"
  local original_dir="$(pwd)"
  
  rm -rf $working_path
  git clone $repo_url -b master --depth=1 $working_path
  cd $working_path

  env LDFLAGS="-static" make
  local binary_path="$working_path/src/unionfs"
  cp $binary_path $out_path
}

rootfs_dir=$(realpath $1)
target_dir=$(realpath $2)
shim_path=$(realpath $3)

shim_rootfs="/tmp/shim_rootfs"
modules_squashfs="/tmp/modules.squashfs"
kernel_dir=/tmp/shim_kernel
initramfs_dir=/tmp/shim_initramfs

echo "compiling unionfs-fuse"
compile_unionfs /tmp/unionfs /tmp/unionfs-fuse 

echo "mounting shim"
shim_loop=$(create_loop "${shim_path}")
make_mountable "${shim_loop}p3"
safe_mount "${shim_loop}p3" $shim_rootfs

echo "extracting modules from shim"
extract_modules $modules_squashfs $shim_rootfs

echo "copying shim kernel"
mkdir $kernel_dir -p
kernel_loop="${shim_loop}p2"
dd if=$kernel_loop of=$kernel_dir/kernel.bin bs=1M status=none

echo "extracting initramfs from kernel"
extract_initramfs $kernel_dir/kernel.bin $kernel_dir $rootfs_dir

#todo...

echo "cleaning up"
umount $shim_rootfs
losetup -d $shim_loop