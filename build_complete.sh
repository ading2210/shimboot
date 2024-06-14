#!/bin/bash

. ./common.sh
. ./image_utils.sh

print_help() {
  echo "Usage: ./build_complete.sh board_name"
  echo "Valid named arguments (specify with 'key=value'):"
  echo "  compress_img - Compress the final disk image into a zip file. Set this to any value to enable this option."
  echo "  rootfs_dir   - Use a different rootfs for the build. The directory you select will be copied before any patches are applied."
  echo "  quiet        - Don't use progress indicators which may clog up log files."
  echo "  desktop      - The desktop environment to install. This defaults to 'xfce'. Valid options include:"
  echo "                   gnome, xfce, kde, lxde, gnome-flashback, cinnamon, mate, lxqt"
  echo "  data_dir     - The working directory for the scripts. This defaults to ./data"
  echo "  arch         - The CPU architecture to build the shimboot image for. Set this to 'arm64' if you have an ARM Chromebook."
  echo "  release      - Set this to either 'bookworm' or 'unstable' to build for Debian stable/unstable."
}

assert_root
assert_args "$1"
parse_args "$@"

base_dir="$(realpath -m  $(dirname "$0"))"
board="$1"

compress_img="${args['compress_img']}"
rootfs_dir="${args['rootfs_dir']}"
quiet="${args['quiet']}"
desktop="${args['desktop']-'xfce'}"
data_dir="${args['data_dir']}"
arch="${args['arch']-amd64}"
release="${args['release']-bookworm}"

arm_boards="
  corsola hana jacuzzi kukui strongbad nyan-big kevin bob
  veyron-speedy veyron-jerry veyron-minnie scarlet elm
  kukui peach-pi peach-pit stumpy daisy-spring
"
if grep -q "$board" <<< "$arm_boards"; then
  echo "automatically detected arm64 device name"
  arch="arm64"
fi

needed_deps="wget python3 unzip zip git debootstrap cpio binwalk pcregrep cgpt mkfs.ext4 mkfs.ext2 fdisk depmod findmnt lz4 pv"
if [ "$(check_deps "$needed_deps")" ]; then
  #install deps automatically on debian and ubuntu
  if [ -f "/etc/debian_version" ]; then
    echo "attempting to install build deps"
    apt-get install wget python3-all unzip zip debootstrap cpio binwalk pcregrep cgpt kmod pv lz4 -y
    if [ "$arch" = "arm64" ]; then
      apt-get install qemu-user-static binfmt-support -y
    fi
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

shim_url="https://dl.darkn.bio/api/raw/?path=/SH1mmer/$board.zip"
boards_url="https://chromiumdash.appspot.com/cros/fetch_serving_builds?deviceCategory=ChromeOS"

if [ -z "$data_dir" ]; then
  data_dir="$base_dir/data"
else
  data_dir="$(realpath -m "$data_dir")"
fi

echo "downloading list of recovery images"
reco_url="$(wget -qO- --show-progress $boards_url | python3 -c '
import json, sys

all_builds = json.load(sys.stdin)
board = all_builds["builds"][sys.argv[1]]
if "models" in board:
  for device in board["models"].values():
    if device["pushRecoveries"]:
      board = device
      break

reco_url = list(board["pushRecoveries"].values())[-1]
print(reco_url)
' $board)"
echo "found url: $reco_url"

shim_bin="$data_dir/shim_$board.bin"
shim_zip="$data_dir/shim_$board.zip"
reco_bin="$data_dir/reco_$board.bin"
reco_zip="$data_dir/reco_$board.zip"
mkdir -p "$data_dir"

download_and_unzip() {
  local url="$1"
  local zip_path="$2"
  local bin_path="$3"
  if [ ! -f "$bin_path" ]; then
    if [ ! "$quiet" ]; then
      wget -q --show-progress $url -O $zip_path -c
    else
      wget -q $url -O $zip_path -c
    fi
  fi

  if [ ! -f "$bin_path" ]; then
    cleanup_path="$bin_path"
    echo "extracting $zip_path"
    local total_bytes="$(unzip -lq $zip_path | tail -1 | xargs | cut -d' ' -f1)"
    if [ ! "$quiet" ]; then
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

if [ ! "$rootfs_dir" ]; then
  rootfs_dir="$(realpath -m data/rootfs_$board)"
  desktop_package="task-$desktop-desktop"
  if [ "$(findmnt -T "$rootfs_dir/dev")" ]; then
    sudo umount -l $rootfs_dir/* 2>/dev/null || true
  fi
  rm -rf $rootfs_dir
  mkdir -p $rootfs_dir

  echo "building debian rootfs"
  ./build_rootfs.sh $rootfs_dir $release \
    custom_packages=$desktop_package \
    hostname=shimboot-$board \
    username=user \
    user_passwd=user \
    arch=$arch
fi

echo "patching debian rootfs"
retry_cmd ./patch_rootfs.sh $shim_bin $reco_bin $rootfs_dir "quiet=$quiet"

echo "building final disk image"
final_image="$data_dir/shimboot_$board.bin"
rm -rf $final_image
retry_cmd ./build.sh $final_image $shim_bin $rootfs_dir "quiet=$quiet" "arch=$arch"
echo "build complete! the final disk image is located at $final_image"

echo "cleaning up"
clean_loops

if [ "$compress_img" ]; then
  image_zip="$data_dir/shimboot_$board.zip"
  echo "compressing disk image into a zip file"
  zip -j $image_zip $final_image
  echo "finished compressing the disk file"
  echo "the finished zip file can be found at $image_zip" 
fi