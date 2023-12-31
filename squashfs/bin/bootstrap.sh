#!/bin/busybox sh

#mount the squashfs + unionfs and boot into it

move_mounts() {
  local base_mounts="/sys /proc /dev"
  local newroot_mnt="$1"
  for mnt in $base_mounts; do
    mkdir -p "$newroot_mnt$mnt"
    mount -n -o move "$mnt" "$newroot_mnt$mnt"
  done
}

boot_dir() {
  local target="$1"

  echo "moving mounts to newroot"
  move_mounts $target

  echo "switching root"
  mkdir -p $target/oldroot
  pivot_root $target $target/oldroot

  /bin/bash -c "mount -o bind /oldroot/lib/modules /lib/modules"
  exec /sbin/init < "$TTY1" >> "$TTY1" 2>&1
}

mount_squashfs() {
  mkdir -p /lib/modules /mnt/root_squashfs
  mount /root.squashfs /mnt/root_squashfs
  mount -o bind /mnt/root_squashfs/lib/modules /lib/modules
}

#based on https://github.com/rpodgorny/unionfs-fuse/blob/master/examples/S01a-unionfs-live-cd.sh
mount_unionfs() {
  local chroot_path="/tmp/unionfs"
  local data_path="/data"
  local mountpoint="/newroot"
  local squashfs_path="/mnt/root_squashfs"

  local fuse_options="-o allow_other,suid,dev"
  local unionfs_options="-o cow,chroot=$chroot_path,max_files=32768"

  mkdir -p $data_path 
  mkdir -p $mountpoint
  mkdir -p $chroot_path/root
  mkdir -p $chroot_path/rw
  
  mount -o bind $squashfs_path $chroot_path/root
  mount -o bind $data_path $chroot_path/rw

  modprobe fuse
  unionfs $fuse_options $unionfs_options /root=RO:/rw=RW /newroot
}

main() {
  echo "mounting squashfs"
  mount_squashfs

  echo "mounting unionfs"
  mount_unionfs

  echo "booting unionfs"
  boot_dir /newroot
}

main "$@"
sleep 1d
