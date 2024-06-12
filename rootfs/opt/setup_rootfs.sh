#!/bin/bash

#setup the debian rootfs
#this is meant to be run within the chroot created by debootstrap

set -e
if [ "$DEBUG" ]; then
  set -x
fi

DEBUG="$1"
release_name="$2"
packages="$3"

hostname="$4"
root_passwd="$5"
username="$6"
user_passwd="$7"
enable_root="$8"
disable_base_pkgs="$9"
arch="${10}"

custom_repo="https://shimboot.ading.dev/debian"
custom_repo_domain="shimboot.ading.dev"
sources_entry="deb [trusted=yes arch=$arch] ${custom_repo} ${release_name} main"

export DEBIAN_FRONTEND="noninteractive"

#add shimboot repos
echo -e "${sources_entry}\n$(cat /etc/apt/sources.list)" > /etc/apt/sources.list
tee -a /etc/apt/preferences << END
Package: *
Pin: origin ${custom_repo_domain}
Pin-Priority: 1001
END

#install the patched systemd
apt-get install -y ca-certificates
apt-get update
installed_systemd="$(dpkg-query -W -f='${binary:Package}\n' | grep "systemd")"
apt-get clean
apt-get install --reinstall $installed_systemd

#enable shimboot services
systemctl enable kill-frecon.service

#install base packages
if [ -z "$disable_base_pkgs" ]; then
  apt-get install -y cloud-utils zram-tools sudo command-not-found bash-completion

  #set up zram
  echo "ALGO=lzo" >> /etc/default/zramswap
  echo "PERCENT=50" >> /etc/default/zramswap

  #update apt-file cache
  apt-file update
fi

#set up hostname and username
if [ ! "$hostname" ]; then
  read -p "Enter the hostname for the system: " hostname
fi
echo "${hostname}" > /etc/hostname
tee -a /etc/hosts << END
127.0.0.1 localhost
127.0.1.1 ${hostname}

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
END

#install desktop and other custom packages
apt-get install -y $packages

if [ ! $username ]; then
  read -p "Enter the username for the user account: " username
fi
useradd -m -s /bin/bash -G sudo $username

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
  usermod -a -G sudo $username
fi

echo "Enter a user password:"
set_password "$username" "$user_passwd"

#clean apt caches
apt-get clean