#!/bin/bash

set -e
if [ "$DEBUG" ]; then
  set -x
fi

make_mountable() {
  sh lib/ssd_util.sh --no_resign_kernel --remove_rootfs_verification -i $1
  printf '\000' | dd of=$1 seek=$((0x464 + 3)) conv=notrunc count=1 bs=1 
}

partition_disk() {
  local image_path=$(realpath "${1}")
  local bootloader_size=${2}

  #create partitions
  ( 
    echo g #new gpt disk label

    #create 1MB stateful
    echo n #new partition
    echo #accept default parition number
    echo #accept default first sector
    echo +1M #partition size is 1M

    #create 32MB kernel partition
    echo n
    echo #accept default parition number
    echo #accept default first sector
    echo +32M #partition size is 32M
    echo t #change partition type
    echo #accept default parition number
    echo FE3A2A5D-4F32-41A7-B725-ACCC3285A309 #chromeos kernel type

    #create bootloader partition
    echo n
    echo #accept default parition number
    echo #accept default first sector
    echo "+${bootloader_size}M" #set partition size
    echo t #change partition type
    echo #accept default parition number
    echo 3CB8E202-3B7E-47DD-8A3C-7FF2A13CFCEC #chromeos rootfs type

    #create rootfs partition
    echo n
    echo #accept default parition number
    echo #accept default first sector
    echo #accept default size to fill rest of image

    #write changes
    echo w
  ) | fdisk $image_path
}

create_image() {
  local image_path=$(realpath "${1}")
  local bootloader_size=${2}
  local rootfs_size=${3}
  
  #stateful + kernel + bootloader + rootfs
  local total_size=$((1 + 32 + $bootloader_size + $rootfs_size))
  dd if=/dev/zero of=$image_path bs=1M oflag=sync count=$total_size status=progress

  partition_disk $image_path $bootloader_size
}

create_image ./test.bin 20 200