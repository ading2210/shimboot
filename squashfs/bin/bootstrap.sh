#!/bin/busybox sh

# Mount the squashfs + unionfs and boot into it

# Function to move mounts
move_mounts() {
  local base_mounts="/sys /proc /dev"
  local newroot_mnt="$1"

  for mnt in $base_mounts; do
    mkdir -p "$newroot_mnt$mnt"
    mount -n -o move "$mnt" "$newroot_mnt$mnt"
  done
}

# Function to handle the booting into new root directory
boot_dir() {
  local target="$1"

  echo "Moving mounts to new root..."
  move_mounts "$target"

  echo "Switching root..."
  mkdir -p "$target/oldroot"
  pivot_root "$target" "$target/oldroot"

  # Bind-mount essential modules
  mount -o bind /oldroot/lib/modules /lib/modules
  exec /sbin/init < "$TTY1" >> "$TTY1" 2>&1
}

# Function to mount the squashfs
mount_squashfs() {
  mkdir -p /lib/modules /mnt/root_squashfs
  mount /root.squashfs /mnt/root_squashfs
  mount -o bind /mnt/root_squashfs/lib/modules /lib/modules
}

# Function to mount the unionfs with necessary options
mount_unionfs() {
  local chroot_path="/tmp/unionfs"
  local data_path="/data"
  local mountpoint="/newroot"
  local squashfs_path="/mnt/root_squashfs"
  local fuse_options="-o allow_other,suid,dev"
  local unionfs_options="-o cow,chroot=$chroot_path,max_files=32768"

  mkdir -p "$data_path" "$mountpoint" "$chroot_path/root" "$chroot_path/rw"

  mount -o bind "$squashfs_path" "$chroot_path/root"
  mount -o bind "$data_path" "$chroot_path/rw"

  modprobe fuse
  unionfs $fuse_options $unionfs_options /root=RO:/rw=RW "$mountpoint"
}

# Main function to orchestrate the steps
main() {
  echo "Mounting squashfs..."
  mount_squashfs

  echo "Mounting unionfs..."
  mount_unionfs

  echo "Booting into unionfs..."
  boot_dir /newroot
}

main "$@"
sleep 1d
