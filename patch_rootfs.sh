#!/bin/bash

#patch the target rootfs to add any needed drivers

set -e
if [ "$DEBUG" ]; then
  set -x
fi

. ./common.sh
. ./image_utils.sh

print_help() {
  echo "Usage: ./patch_rootfs.sh shim_path reco_path rootfs_dir"
}

assert_root
assert_deps "git gunzip"
assert_args "$3"

if [ -z "$3" ]; then
  print_help
  exit 1
fi

copy_modules() {
  local shim_rootfs=$(realpath -m $1)
  local reco_rootfs=$(realpath -m $2)
  local target_rootfs=$(realpath -m $3)

  rm -rf "${target_rootfs}/lib/modules"
  cp -r "${shim_rootfs}/lib/modules" "${target_rootfs}/lib/modules"

  mkdir -p "${target_rootfs}/lib/firmware"
  cp -r --remove-destination "${shim_rootfs}/lib/firmware/"* "${target_rootfs}/lib/firmware/"
  cp -r --remove-destination "${reco_rootfs}/lib/firmware/"* "${target_rootfs}/lib/firmware/"

  mkdir -p "${target_rootfs}/lib/modprobe.d/"
  mkdir -p "${target_rootfs}/etc/modprobe.d/"
  cp -r "${reco_rootfs}/lib/modprobe.d/"* "${target_rootfs}/lib/modprobe.d/"
  cp -r "${reco_rootfs}/etc/modprobe.d/"* "${target_rootfs}/etc/modprobe.d/"

  #decompress kernel modules if necessary - debian won't recognize these otherwise
  find "${target_rootfs}/lib/modules" -name "*.gz" | xargs gunzip
}

copy_firmware() {
  local firmware_path="/tmp/chromium-firmware"
  local target_rootfs=$(realpath -m $1)

  if [ ! -e "$firmware_path" ]; then
    download_firmware $firmware_path
  fi

  cp -r --remove-destination "${firmware_path}/"* "${target_rootfs}/lib/firmware/"
}

download_firmware() {
  local firmware_url="https://chromium.googlesource.com/chromiumos/third_party/linux-firmware"
  local firmware_path=$(realpath -m $1)

  git clone --branch master --depth=1 "${firmware_url}" $firmware_path
}

shim_path=$(realpath -m $1)
reco_path=$(realpath -m $2)
target_rootfs=$(realpath -m $3)
shim_rootfs="/tmp/shim_rootfs"
reco_rootfs="/tmp/reco_rootfs"

echo "mounting shim"
shim_loop=$(create_loop "${shim_path}")
make_mountable "${shim_loop}p3"
safe_mount "${shim_loop}p3" $shim_rootfs

echo "mounting recovery image"
reco_loop=$(create_loop "${reco_path}")
make_mountable "${reco_loop}p3"
safe_mount "${reco_loop}p3" $reco_rootfs

echo "copying modules to rootfs"
copy_modules $shim_rootfs $reco_rootfs $target_rootfs

echo "downloading misc firmware"
copy_firmware $target_rootfs

echo "unmounting and cleaning up"
umount $shim_rootfs
umount $reco_rootfs
losetup -d $shim_loop
losetup -d $reco_loop

echo "done"