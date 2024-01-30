#!/bin/bash

set -e
if [ "$DEBUG" ]; then
  set -x
  export DEBUG=1
fi

. ./common.sh

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

if [ -z "$1" ]; then
  echo "Usage: ./build_complete.sh board_name"
  echo "Valid named arguments (specify with 'key=value'):"
  echo "  compress_img - Compress the final disk image into a zip file. Set this to any value to enable this option."
  echo "  rootfs_dir   - Use a different rootfs for the build. The directory you select will be copied before any patches are applied."
  echo "  quiet        - Don't use progress indicators which may clog up log files."
  exit 1
fi

parse_args "$@"
needed_deps="wget python3 unzip zip git debootstrap cpio binwalk pcregrep cgpt mkfs.ext4 mkfs.ext2 fdisk rsync"
if [ "$(check_deps "$needed_deps")" ]; then
  #install deps automatically on debian and ubuntu
  if [ -f "/etc/debian_version" ]; then
    echo "attempting to install build deps"
    apt-get install wget python3-all unzip zip debootstrap cpio binwalk pcregrep cgpt rsync pv -y
  fi
  assert_deps "$needed_deps"
fi

cleanup_path=""
sigint_handler() {
  if [ $cleanup_path ]; then
    rm -rf $cleanup_path
  fi
  exit 1
}
trap sigint_handler SIGINT

base_dir="$(realpath -m  $(dirname "$0"))"
board="$1"
shim_url="https://dl.osu.bio/api/raw/?path=/SH1mmer/$board.zip"
boards_url="https://chromiumdash.appspot.com/cros/fetch_serving_builds?deviceCategory=ChromeOS"

echo "downloading list of recovery images"
reco_url="$(wget -qO- --show-progress $boards_url | python3 -c '
import json, sys

all_builds = json.load(sys.stdin)
board = all_builds["builds"][sys.argv[1]]
if "models" in board:
  board = next(iter(board["models"].values()))

reco_url = list(board["pushRecoveries"].values())[-1]
print(reco_url)
' $board)"
echo "found url: $reco_url"

shim_bin="$base_dir/data/shim_$board.bin"
shim_zip="$base_dir/data/shim_$board.zip"
reco_bin="$base_dir/data/reco_$board.bin"
reco_zip="$base_dir/data/reco_$board.zip"
mkdir -p "$base_dir/data"

download_and_unzip() {
  local url="$1"
  local zip_path="$2"
  local bin_path="$3"
  if [ ! -f "$bin_path" ]; then
    if [ ! "${args['quiet']}" ]; then
      wget -q --show-progress $url -O $zip_path -c
    else
      wget -q $url -O $zip_path -c
    fi
  fi

  if [ ! -f "$bin_path" ]; then
    cleanup_path="$bin_path"
    echo "extracting $zip_path"
    local total_bytes="$(unzip -lq $zip_path | tail -1 | xargs | cut -d' ' -f1)"
    if [ ! "${args['quiet']}" ]; then
      unzip -p $zip_path | pv -s $total_bytes > $bin_path
    else
      unzip -p $zip_path > $bin_path
    fi
    rm -rf $zip_path
    cleanup_path=""
  fi
}

retry_cmd() {
  local cmd="$@"
  for i in 1 2 3 4 5; do
    $cmd && break
  done
}

echo "downloading recovery image"
download_and_unzip $reco_url $reco_zip $reco_bin

echo "downloading shim image"
download_and_unzip $shim_url $shim_zip $shim_bin

if [ ! "${args['rootfs_dir']}" ]; then
  rootfs_dir="$(realpath -m data/rootfs_$board)"
  rm -rf $rootfs_dir
  mkdir -p $rootfs_dir

  echo "building debian rootfs"
  ./build_rootfs.sh $rootfs_dir bookworm \
    hostname=shimboot-$board \
    root_passwd=root \
    username=user \
    user_passwd=user  
else
  rootfs_dir="$(realpath -m "${args['rootfs_dir']}")"
fi

echo "patching debian rootfs"
retry_cmd ./patch_rootfs.sh $shim_bin $reco_bin $rootfs_dir "quiet=${args['quiet']}"

echo "building final disk image"
final_image="$base_dir/data/shimboot_$board.bin"
rm -rf $final_image
retry_cmd ./build.sh $final_image $shim_bin $rootfs_dir "quiet=${args['quiet']}"
echo "build complete! the final disk image is located at $final_image"

if [ "${args['compress_img']}" ]; then
  image_zip="$base_dir/data/shimboot_$board.zip"
  echo "compressing disk image into a zip file"
  zip -j $image_zip $final_image
  echo "finished compressing the disk file"
  echo "the finished zip file can be found at $image_zip" 
fi