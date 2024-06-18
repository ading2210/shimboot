#!/bin/bash

#build a rootfs that uses a squashfs + unionfs
#consists of a minimal busybox system containing:
# - FUSE kernel modules from the shim
# - unionfs-fuse statically compiled 
# - the main squashfs, compressed with gzip

set -e
if [ "$DEBUG" ]; then
  set -x
fi

. ./common.sh
. ./image_utils.sh
. ./shim_utils.sh

print_help() {
  echo "Usage: ./build_squashfs.sh rootfs_dir uncompressed_rootfs_dir path_to_shim"
}

assert_root
assert_deps "git make gcc binwalk pcregrep"
assert_args "$3"

compile_unionfs() {
  local out_path="$1"
  local working_path="$2"

  local repo_url="https://github.com/rpodgorny/unionfs-fuse"
  local original_dir="$(pwd)"
  local core_count="$(nproc --all)"
  
  rm -rf $working_path
  git clone $repo_url -b master --depth=1 $working_path
  cd $working_path

  env LDFLAGS="-static" CFLAGS="-O3" make -j$core_count
  local binary_path="$working_path/src/unionfs"
  cp $binary_path $out_path
  cd $original_dir
}

rootfs_dir=$(realpath -m $1)
old_dir=$(realpath -m $2)
shim_path=$(realpath -m $3)

shim_rootfs="/tmp/shim_rootfs"
root_squashfs="$rootfs_dir/root.squashfs"
modules_squashfs="$rootfs_dir/modules.squashfs"
unionfs_dir="/tmp/unionfs-fuse"

print_info "compiling unionfs-fuse"
compile_unionfs $unionfs_dir/unionfs $unionfs_dir

print_info "reading the shim image"
extract_initramfs_full $shim_path $rootfs_dir
rm -rf $rootfs_dir/init

print_info "compressing old rootfs"
mksquashfs $old_dir $root_squashfs -noappend -comp gzip

print_info "patching new rootfs"
mv $unionfs_dir/unionfs $rootfs_dir/bin/unionfs
cp -ar squashfs/* $rootfs_dir/
chmod +x $rootfs_dir/bin/*

print_info "done"