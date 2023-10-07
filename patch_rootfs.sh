#!/bin/bash

#patch the target rootfs to add any needed drivers

set -e
if [ "$DEBUG" ]; then
  set -x
fi

patch_rootfs() {
  local shim_rootfs=$(realpath $1)
  local target_rootfs=$(realpath $2)

  cp -r "${shim_rootfs}/lib/modules/"* "${target_rootfs}/lib/modules/"
  cp -r "${shim_rootfs}/lib/modprobe.d/"* "${target_rootfs}/lib/modprobe.d/"
  cp -r "${shim_rootfs}/etc/modprobe.d/"* "${target_rootfs}/etc/modprobe.d/"
  cp -r "${shim_rootfs}/lib/firmware/"* "${target_rootfs}/lib/firmware/"
}

patch_rootfs $1 $2