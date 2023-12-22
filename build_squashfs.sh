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
  local core_count="$(nproc --all)"
  
  rm -rf $working_path
  git clone $repo_url -b master --depth=1 $working_path
  cd $working_path

  env LDFLAGS="-static" make -j$core_count
  local binary_path="$working_path/src/unionfs"
  cp $binary_path $out_path
  cd $original_dir
}

rootfs_dir=$(realpath $1)
old_dir=$(realpath $2)
shim_path=$(realpath $3)

shim_rootfs="/tmp/shim_rootfs"
root_squashfs="$rootfs_dir/root.squashfs"
modules_squashfs="$rootfs_dir/modules.squashfs"
kernel_dir=/tmp/shim_kernel
unionfs_dir="/tmp/unionfs-fuse"

echo "compiling unionfs-fuse"
compile_unionfs $unionfs_dir/unionfs $unionfs_dir

echo "creating loop device for shim"
shim_loop=$(create_loop "${shim_path}")
kernel_loop="${shim_loop}p2" #KERN-A should always be p2

echo "copying shim kernel"
rm -rf $kernel_dir
mkdir $kernel_dir -p
dd if=$kernel_loop of=$kernel_dir/kernel.bin bs=1M status=progress

echo "extracting initramfs from kernel (this may take a while)"
extract_initramfs $kernel_dir/kernel.bin $kernel_dir $rootfs_dir
rm -rf $rootfs_dir/init

echo "mounting shim"
make_mountable "${shim_loop}p3"
safe_mount "${shim_loop}p3" $shim_rootfs

echo "compressing old rootfs"
mksquashfs $old_dir $root_squashfs -noappend -comp gzip

echo "patching new rootfs"
mv $unionfs_dir/unionfs $rootfs_dir/bin/unionfs
cp -ar squashfs/* $rootfs_dir/
chmod +x $rootfs_dir/bin/*

echo "done"