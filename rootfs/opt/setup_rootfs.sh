#!/bin/bash

#setup the debian rootfs
#this is meant to be run within the chroot created by debootstrap

set -e
if [ "$DEBUG" ]; then
  set -x
fi

custom_repo="https://shimboot.ading.dev/debian"
custom_repo_domain="shimboot.ading.dev"
sources_entry="deb [trusted=yes] ${custom_repo} ${release_name} main"

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
apt-get upgrade -y 

#enable shimboot services
systemctl enable kill-frecon.service

#install desktop
apt-get install -y task-xfce-desktop cloud-utils zram-tools

#set up zram
tee -a /etc/default/zramswap << END
ALGO=lzo
PERCENT=50
END

#set up hostname and username
read -p "Enter the hostname for the system: " hostname
echo "${hostname}" > /etc/hostname
tee -a /etc/hosts << END
127.0.0.1 localhost
127.0.1.1 ${hostname}

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
END

echo "Enter a root password:"
passwd root

read -p "Enter the username for the user account: " username
useradd -m -s /bin/bash -G sudo $username
echo "Enter the password for ${username}:"
passwd $username

#clean apt caches
apt-get clean