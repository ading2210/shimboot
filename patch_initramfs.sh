#!/bin/bash

#patch the shim initramfs to add the bootloader

set -e
if [ "$DEBUG" ]; then
  set -x
fi

patch_initramfs() {
  local initramfs_path=$(realpath $1)

  rm "${initramfs_path}/init" -f
  cp -r bootloader/* "${initramfs_path}/"

  find ${initramfs_path}/bin -name "*" -exec chmod +x {} \;
}
