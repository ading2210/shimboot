#!/bin/bash

#patch the target rootfs to add any needed drivers

set -e
if [ "$DEBUG" ]; then
  set -x
fi

copy_modules() {
  local shim_rootfs=$(realpath $1)
  local reco_rootfs=$(realpath $2)
  local target_rootfs=$(realpath $3)

  cp -r "${shim_rootfs}/lib/modules/"* "${target_rootfs}/lib/modules/"
  cp -r "${shim_rootfs}/lib/firmware/"* "${target_rootfs}/lib/firmware/"
  cp -r "${reco_rootfs}/lib/modprobe.d/"* "${target_rootfs}/lib/modprobe.d/"
  cp -r "${reco_rootfs}/etc/modprobe.d/"* "${target_rootfs}/etc/modprobe.d/"
}

download_firmware() {
  local firmware_url="https://chromium.googlesource.com/chromiumos/third_party/linux-firmware"
  local firmware_path="/tmp/chromium-firmware"

  git clone --branch master --depth=1 "${firmware_url}" $firmware_path
}