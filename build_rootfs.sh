#!/bin/bash

#build the debian rootfs

set -e
if [ "$DEBUG" ]; then
  set -x
fi

print_help() {
  echo "Usage: ./build_rootfs.sh rootfs_path release_name [custom_packages]"
}

check_deps() {
  local needed_commands="realpath debootstrap"
  for command in $needed_commands; do
    if ! command -v $command &> /dev/null; then
      echo $command
    fi
  done
}

if [ "$EUID" -ne 0 ]; then
  echo "this needs to be run as root."
  exit 1
fi

if [ -z "$2" ]; then
  print_help
  exit 1
fi

missing_commands=$(check_deps)
if [ "${missing_commands}" ]; then
  echo "You are missing dependencies needed for this script."
  echo "Commands needed:"
  echo "${missing_commands}"
  exit 1
fi

rootfs_dir=$(realpath "${1}")
release_name="${2}"
packages="${3-'task-xfce-desktop'}"

debootstrap --arch amd64 $release_name $rootfs_dir http://deb.debian.org/debian/
cp -ar rootfs/* $rootfs_dir

chroot_mounts="proc sys dev run"
for mountpoint in $chroot_mounts; do
  mount --make-rslave --rbind "/${mountpoint}" "${rootfs_dir}/$mountpoint"
done

chroot_command="/opt/setup_rootfs.sh '$DEBUG' '$release_name' '$packages'"
chroot $rootfs_dir /bin/bash -c "${chroot_command}"

for mountpoint in $chroot_mounts; do
  umount -l "${rootfs_dir}/$mountpoint"
done

echo "rootfs has been created"