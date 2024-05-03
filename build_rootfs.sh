#!/bin/bash

#build the debian rootfs

set -e
if [ "$DEBUG" ]; then
  set -x
fi

. ./common.sh

print_help() {
  echo "Usage: ./build_rootfs.sh rootfs_path release_name"
  echo "Valid named arguments (specify with 'key=value'):"
  echo "  custom_packages - The packages that will be installed in place of task-xfce-desktop."
  echo "  hostname        - The hostname for the new rootfs."
  echo "  enable_root     - Enable the root user."
  echo "  root_passwd     - The root password. This only has an effect if enable_root is set."
  echo "  username        - The unprivileged user name for the new rootfs."
  echo "  user_passwd     - The password for the unprivileged user."
  echo "  disable_base    - Disable the base packages such as zram, cloud-utils, and command-not-found."
  echo "If you do not specify the hostname and credentials, you will be prompted for them later."
}

assert_root
assert_deps "realpath debootstrap"
assert_args "$2"
parse_args "$@"

rootfs_dir=$(realpath -m "${1}")
release_name="${2}"
packages="${args['custom_packages']-'task-xfce-desktop'}"
chroot_mounts="proc sys dev run"

mkdir -p $rootfs_dir

unmount_all() {
  for mountpoint in $chroot_mounts; do
    umount -l "$rootfs_dir/$mountpoint"
  done
}

debootstrap --arch amd64 $release_name $rootfs_dir http://deb.debian.org/debian/
cp -ar rootfs/* $rootfs_dir
cp /etc/resolv.conf $rootfs_dir/etc/resolv.conf

trap unmount_all EXIT
for mountpoint in $chroot_mounts; do
  mount --make-rslave --rbind "/${mountpoint}" "${rootfs_dir}/$mountpoint"
done

hostname="${args['hostname']}"
root_passwd="${args['root_passwd']}"
enable_root="${args['enable_root']}"
username="${args['username']}"
user_passwd="${args['user_passwd']}"
disable_base="${args['disable_base']}"

chroot_command="/opt/setup_rootfs.sh \
  '$DEBUG' '$release_name' '$packages' \
  '$hostname' '$root_passwd' '$username' \
  '$user_passwd' '$enable_root' '$disable_base'"

LC_ALL=C chroot $rootfs_dir /bin/bash -c "${chroot_command}"

trap - EXIT
unmount_all

echo "rootfs has been created"