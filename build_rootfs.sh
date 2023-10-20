#!/bin/bash

#build the debian rootfs

set -e
if [ "$DEBUG" ]; then
  set -x
fi

print_help() {
  echo "Usage: ./build_rootfs.sh rootfs_path release_name"
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

debootstrap $release_name $rootfs_dir http://deb.debian.org/debian/
cp -r rootfs/* $rootfs_dir
chroot_command="DEBUG=${DEBUG} release_name=${release_name} /opt/setup_rootfs.sh"
chroot $rootfs_dir /bin/bash -c "${chroot_command}"

echo "rootfs has been created"