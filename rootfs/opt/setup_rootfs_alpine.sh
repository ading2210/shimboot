#!/bin/sh

#setup the alpine linux rootfs
#this is meant to be run within the chroot created by build_rootfs.sh

DEBUG="$1"
set -e
if [ "$DEBUG" ]; then
  set -x
fi

release_name="$2"
packages="$3"
hostname="$4"
root_passwd="$5"
username="$6"
user_passwd="$7"
enable_root="$8"
disable_base_pkgs="$9"
arch="${10}"

#set hostname and apk repos
setup-hostname "$hostname"
setup-apkrepos \
  "http://dl-cdn.alpinelinux.org/alpine/$release_name/main/" \
  "http://dl-cdn.alpinelinux.org/alpine/$release_name/community/"

#enable services on startup
rc-update add acpid default
rc-update add bootmisc boot
rc-update add crond default
rc-update add devfs sysinit
rc-update add sysfs sysinit
rc-update add dmesg sysinit
rc-update add hostname boot
rc-update add hwclock boot
rc-update add hwdrivers sysinit
rc-update add killprocs shutdown
rc-update add mdev sysinit
rc-update add modules boot
rc-update add mount-ro shutdown
rc-update add networking boot
rc-update add savecache shutdown
rc-update add seedrng boot
rc-update add swap boot
rc-update add syslog boot

#add service to kill frecon
echo "#!/sbin/openrc-run

command='/usr/bin/pkill frecon-lite'
" > /etc/init.d/kill-frecon
chmod +x /etc/init.d/kill-frecon
rc-update add kill-frecon boot

#setup the desktop
if echo "$packages" | grep "task-" >/dev/null; then
  desktop="$(echo $packages | cut -d'-' -f2)"
  setup-desktop $desktop

else
  apk add $packages
fi

#openrc doesnt work with /etc/modules-load.d for some reason 
#so we need to copy those to /etc/modules
module_files="$(ls /etc/modules-load.d)"
for mod_file in $module_files; do
  cat "/etc/modules-load.d/$mod_file" >> /etc/modules
  echo >> /etc/modules
done

#install base packages
if [ -z "$disable_base_pkgs" ]; then
  #install various packages
  apk add elogind polkit-elogind udisks2 polkit-elogind sudo zram-init networkmanager networkmanager-tui networkmanager-wifi network-manager-applet wpa_supplicant adw-gtk3 cloud-utils-growpart nano mousepad
  
  #start desktop services
  rc-update add networkmanager default
  rc-update add wpa_supplicant default
  rc-update add zram-init default
  rc-update add elogind default
  rc-update add dbus default

  #configure zram
  sed -i 's/=zstd/=lzo/' /etc/conf.d/zram-init #set lzo algorithm
  sed -i '/size0=512/d' /etc/conf.d/zram-init #disable default swap size
  sed -i '/blk1=1024/d' /etc/conf.d/zram-init #disable default /tmp block size
  echo "size0=\`LC_ALL=C free -m | awk '/^Mem:/{print int(\$2/2)}'\`" >> /etc/conf.d/zram-init #set swap size to half of physical

  #configure networkmanager
  mkdir -p /etc/NetworkManager/conf.d
  echo -e "[main]\nauth-polkit=false" > /etc/NetworkManager/conf.d/any-user.conf
fi

if [ ! $username ]; then
  read -p "Enter the username for the user account: " username
fi
useradd -m $username
usermod -G netdev -a $username
usermod -G plugdev -a $username
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

set_password() {
  local user="$1"
  local password="$2"
  if [ ! "$password" ]; then
    while ! passwd $user; do
      echo "Failed to set password for $user, please try again."
    done
  else
    yes "$password" | passwd $user
  fi
}

if [ "$enable_root" ]; then 
  echo "Enter a root password:"
  set_password root "$root_passwd"
else
  usermod -a -G wheel $username
fi

echo "Enter a user password:"
set_password "$username" "$user_passwd"
