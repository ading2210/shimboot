#!/bin/bash

#patch the shim initramfs to add the bootloader

set -e
if [ "$DEBUG" ]; then
  set -x
fi

initramfs_path=$(realpath $1)

rm "${initramfs_path}/init" -f
cp bootloader/init.sh "${initramfs_path}/bin/init"
cp bootloader/bootstrap.sh "${initramfs_path}/bin/bootstrap.sh"

find ${initramfs_path}/bin -name "*" -exec chmod +x {} \;