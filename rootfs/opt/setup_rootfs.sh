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

#install desktop
apt-get install -y xfce4 xfce4-goodies network-manager blueman firefox-esr sudo