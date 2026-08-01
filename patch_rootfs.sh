#!/bin/bash

#patch the target rootfs to add any needed drivers

. ./common.sh
. ./image_utils.sh

print_help() {
  echo "Usage: ./patch_rootfs.sh shim_path reco_path rootfs_dir [board]"
  echo "If board is provided, the script will also look for data/board_modules/<board>/"
}

assert_root
assert_deps "git gunzip depmod"
assert_args "$3"

# board can be passed as 4th positional argument or via BOARD env var
board_arg="${4:-${BOARD-}}"

copy_modules() {
  local shim_rootfs=$(realpath -m $1)
  local reco_rootfs=$(realpath -m $2)
  local target_rootfs=$(realpath -m $3)

  rm -rf "${target_rootfs}/lib/modules"
  cp -r "${shim_rootfs}/lib/modules" "${target_rootfs}/lib/modules"

  mkdir -p "${target_rootfs}/lib/firmware"
  cp -r --remove-destination "${shim_rootfs}/lib/firmware/"* "${target_rootfs}/lib/firmware/" 2>/dev/null || true
  cp -r --remove-destination "${reco_rootfs}/lib/firmware/"* "${target_rootfs}/lib/firmware/" 2>/dev/null || true

  mkdir -p "${target_rootfs}/lib/modprobe.d/"
  mkdir -p "${target_rootfs}/etc/modprobe.d/"
  cp -r "${reco_rootfs}/lib/modprobe.d/"* "${target_rootfs}/lib/modprobe.d/" 2>/dev/null || true
  cp -r "${reco_rootfs}/etc/modprobe.d/"* "${target_rootfs}/etc/modprobe.d/" 2>/dev/null || true

  #decompress kernel modules if necessary - debian won't recognize these otherwise
  local compressed_files="$(find "${target_rootfs}/lib/modules" -name '*.gz' 2>/dev/null)"
  if [ "$compressed_files" ]; then
    echo "$compressed_files" | xargs gunzip
    for kernel_dir in "$target_rootfs/lib/modules/"*; do
      [ -d "$kernel_dir" ] || continue
      local version="$(basename "$kernel_dir")"
      depmod -b "$target_rootfs" "$version"
    done
  fi
}

copy_firmware() {
  local firmware_path="/tmp/chromium-firmware"
  local target_rootfs=$(realpath -m $1)

  if [ ! -e "$firmware_path" ]; then
    download_firmware $firmware_path
  fi

  cp -r --remove-destination "${firmware_path}/"* "${target_rootfs}/lib/firmware/" 2>/dev/null || true
}

download_firmware() {
  local firmware_url="https://chromium.googlesource.com/chromiumos/third_party/linux-firmware"
  local firmware_path=$(realpath -m $1)

  git clone --branch master --depth=1 "${firmware_url}" $firmware_path
}

# New: copy board-specific modules/firmware from data/board_modules/<board> into rootfs
copy_board_modules() {
  local board="$1"
  local target_rootfs=$(realpath -m $2)
  local modules_dir="data/board_modules/${board}"

  if [ -z "$board" ] || [ ! -d "$modules_dir" ]; then
    return
  fi

  echo "copying board-specific modules/firmware from $modules_dir to $target_rootfs"

  # If a tarball of modules exists, extract it into lib/modules
  if [ -f "${modules_dir}/modules.tar.gz" ]; then
    mkdir -p "${target_rootfs}/lib/modules"
    tar -xzf "${modules_dir}/modules.tar.gz" -C "${target_rootfs}/lib/modules"
  fi

  # Copy any lib/modules tree directly
  if [ -d "${modules_dir}/lib/modules" ]; then
    mkdir -p "${target_rootfs}/lib/modules"
    cp -r --remove-destination "${modules_dir}/lib/modules/"* "${target_rootfs}/lib/modules/"
  fi

  # Copy firmware if provided
  if [ -d "${modules_dir}/lib/firmware" ]; then
    mkdir -p "${target_rootfs}/lib/firmware"
    cp -r --remove-destination "${modules_dir}/lib/firmware/"* "${target_rootfs}/lib/firmware/"
  fi

  # run depmod for each kernel version present
  for kernel_dir in "${target_rootfs}/lib/modules/"*; do
    [ -d "$kernel_dir" ] || continue
    version="$(basename "$kernel_dir")"
    depmod -b "${target_rootfs}" "$version" || true
  done
}

shim_path=$(realpath -m $1)
reco_path=$(realpath -m $2)
target_rootfs=$(realpath -m $3)
shim_rootfs="/tmp/shim_rootfs"
reco_rootfs="/tmp/reco_rootfs"

echo "mounting shim"
shim_loop=$(create_loop "${shim_path}")
safe_mount "${shim_loop}p3" $shim_rootfs ro

echo "mounting recovery image"
reco_loop=$(create_loop "${reco_path}")
safe_mount "${reco_loop}p3" $reco_rootfs ro

echo "copying modules to rootfs"
copy_modules $shim_rootfs $reco_rootfs $target_rootfs

echo "downloading misc firmware"
copy_firmware $target_rootfs

# New: copy any board-specific modules/firmware if present
if [ "$board_arg" ]; then
  copy_board_modules "$board_arg" "$target_rootfs"
fi

echo "unmounting and cleaning up"
umount $shim_rootfs
umount $reco_rootfs
losetup -d $shim_loop
losetup -d $reco_loop

echo "done"
