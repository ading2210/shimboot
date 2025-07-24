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
  echo "  release      - Set this to either 'bookworm', 'trixie', or 'unstable' to build for Debian 12, 13, or unstable."
  echo "  distro       - The Linux distro to use. This should be either 'debian', 'ubuntu', or 'alpine'."
  echo "  luks         - Set this argument to encrypt the rootfs partition."
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
release="${args['release']}"
distro="${args['distro']-debian}"
luks="${args['luks']}"

#a list of all arm board names
arm_boards="
  corsola hana jacuzzi kukui strongbad nyan-big kevin bob
  veyron-speedy veyron-jerry veyron-minnie scarlet elm
  kukui peach-pi peach-pit stumpy daisy-spring trogdor
"
#a list of shims that have a patch for the sh1mmer vulnerability
bad_boards="reef sand pyro"

if grep -q "$board" <<< "$arm_boards" > /dev/null; then
  print_info "automatically detected arm64 device name"
  arch="arm64"
fi
if grep -q "$board" <<< "$bad_boards" > /dev/null; then
  print_error "Warning: you are attempting to build Shimboot for a board which has a shim that includes a fix for the sh1mmer vulnerability. The resulting image will not boot if you are enrolled."
  read -p "Press [enter] to continue "
fi

if [[ "$luks" == "true" && "$arch" == "arm64" ]]; then
  print_error "Uh-oh, you are trying to use luks2 encryption on an arm64 board. Unfortunately, rootfs encryption is not available on arm64-based boards at this time. :("
  exit
fi

kernel_arch="$(uname -m)"
host_arch="unknown"
if [ "$kernel_arch" = "x86_64" ]; then
  host_arch="amd64"
elif [ "$kernel_arch" = "aarch64" ]; then
  host_arch="arm64"
fi

needed_deps="curl wget python3 unzip zip git debootstrap cpio binwalk pcregrep cgpt mkfs.ext4 mkfs.ext2 fdisk depmod findmnt lz4 pv cryptsetup"
if [ "$(check_deps "$needed_deps")" ]; then
  #install deps automatically on debian and ubuntu
  if [ -f "/etc/debian_version" ]; then
    print_title "attempting to install build deps"
    apt-get install wget python3 unzip zip debootstrap cpio binwalk pcregrep cgpt kmod pv lz4 cryptsetup -y
  fi
  assert_deps "$needed_deps"
fi

#install qemu-user-static on debian if needed
if [ "$arch" != "$host_arch" ]; then
  if [ -f "/etc/debian_version" ]; then
    if ! dpkg --get-selections | grep -v deinstall | grep "qemu-user-static\|box64\|fex-emu" > /dev/null; then
      print_info "automatically installing qemu-user-static because we are building for a different architecture"
      apt-get install qemu-user-static binfmt-support -y
    fi
  else 
    print_error "Warning: You are building an image for a different CPU architecture. It may fail if you do not have qemu-user-static installed."
    sleep 1
  fi
fi

cleanup_path=""
sigint_handler() {
  if [ $cleanup_path ]; then
    rm -rf $cleanup_path
  fi
  exit 1
}
trap sigint_handler SIGINT

shim_url="" #set this if you want to download from a third party mirror
boards_url="https://chromiumdash.appspot.com/cros/fetch_serving_builds?deviceCategory=ChromeOS"

if [ -z "$data_dir" ]; then
  data_dir="$base_dir/data"
else
  data_dir="$(realpath -m "$data_dir")"
fi

print_title "downloading list of recovery images"
reco_url="$(wget -qO- --show-progress $boards_url | python3 -c '
import json, sys

all_builds = json.load(sys.stdin)
board_name = sys.argv[1]
if not board_name in all_builds["builds"]:
  print("Invalid board name: " + board_name, file=sys.stderr)
  sys.exit(1)
  
board = all_builds["builds"][board_name]
if "models" in board:
  for device in board["models"].values():
    if device["pushRecoveries"]:
      board = device
      break

reco_url = list(board["pushRecoveries"].values())[-1]
print(reco_url)
' $board)"
print_info "found url: $reco_url"

shim_bin="$data_dir/shim_$board.bin"
shim_zip="$data_dir/shim_$board.zip"
shim_dir="$data_dir/shim_${board}_chunks"
reco_bin="$data_dir/reco_$board.bin"
reco_zip="$data_dir/reco_$board.zip"
mkdir -p "$data_dir"

extract_zip() {
  local zip_path="$1"
  local bin_path="$2"
  cleanup_path="$bin_path"
  print_info "extracting $zip_path"
  local total_bytes="$(unzip -lq "$zip_path" | tail -1 | xargs | cut -d' ' -f1)"
  if [ ! "$quiet" ]; then
    unzip -p "$zip_path" | pv -s "$total_bytes" > "$bin_path"
  else
    unzip -p "$zip_path" > "$bin_path"
  fi
  rm -rf "$zip_path"
  cleanup_path=""
}

download_and_unzip() {
  local url="$1"
  local zip_path="$2"
  local bin_path="$3"
  if [ ! -f "$bin_path" ]; then
    if [ ! "$quiet" ]; then
      wget -q --show-progress $url -O "$zip_path" -c
    else
      wget -q "$url" -O "$zip_path" -c
    fi
  fi

  if [ ! -f "$bin_path" ]; then
    extract_zip "$zip_path" "$bin_path"
  fi
}

download_shim() {
  print_info "downloading shim file manifest"
  local boards_index="$(curl --no-progress-meter "https://cdn.cros.download/boards.txt")"
  local shim_url_path="$(echo "$boards_index" | grep "/$board/").manifest"
  local shim_url_dir="$(dirname "$shim_url_path")"
  local shim_manifest="$(curl --no-progress-meter "https://cdn.cros.download/$shim_url_path")"
  local py_load_json="import json, sys; manifest = json.load(sys.stdin)"

  local zip_size="$(echo "$shim_manifest" | python3 -c "$py_load_json; print(manifest['size'])")"
  local zip_size_pretty="$(echo "$zip_size" | numfmt --format %.2f --to=iec)"
  local shim_chunks="$(echo "$shim_manifest" | python3 -c "$py_load_json; print('\\n'.join(manifest['chunks']))")"
  local chunk_count="$(echo "$shim_chunks" | wc -l)"
  local chunk_size="$((25 * 1024 * 1024))"

  print_info "downloading shim file chunks (total $zip_size_pretty across $chunk_count chunks)"
  mkdir -p "$shim_dir"
  local i="0"
  for shim_chunk in $shim_chunks; do
    local chunk_url="https://cdn.cros.download/$shim_url_dir/$shim_chunk"
    local chunk_path="$shim_dir/$shim_chunk"
    local i="$(($i + 1))"
    if [ -f "$chunk_path" ]; then
      local existing_size="$(du -b "$chunk_path" | cut -f1)"
      if [ "$existing_size" = "$chunk_size" ]; then
        continue
      fi
    fi
    print_info "downloading chunk $i / $chunk_count"
    if [ ! "$quiet" ]; then
      wget -c -q --show-progress "$chunk_url" -O "$chunk_path"
    else
      wget -c -q "$chunk_url" -O "$chunk_path"
    fi
  done

  print_info "joining shim file chunks"
  cleanup_path="$shim_zip"
  if [ ! -f "$shim_bin" ]; then
    cat "$shim_dir/"* | pv -s "$zip_size" > "$shim_zip"
    rm -rf "$shim_dir"
  fi
  cleanup_path=""

  print_info "extracting shim file"
  if [ ! -f "$shim_bin" ]; then
    extract_zip "$shim_zip" "$shim_bin"
  fi
}

retry_cmd() {
  local cmd="$@"
  for i in 1 2 3 4 5; do
    $cmd && break
  done
}

print_title "downloading recovery image"
download_and_unzip "$reco_url" "$reco_zip" "$reco_bin"

print_title "downloading shim image"
if [ ! -f "$shim_bin" ]; then
  if [ "$shim_url" ]; then
    download_and_unzip "$shim_url" "$shim_zip" "$shim_bin"
  else
    download_shim "$shim_url" "$shim_zip" "$shim_bin"
  fi
fi

print_title "building $distro rootfs"
if [ ! "$rootfs_dir" ]; then
  desktop_package="task-$desktop-desktop"
  rootfs_dir="$(realpath -m data/rootfs_$board)"
  if [ "$(findmnt -T "$rootfs_dir/dev")" ]; then
    sudo umount -l $rootfs_dir/* 2>/dev/null || true
  fi
  rm -rf $rootfs_dir
  mkdir -p $rootfs_dir

  if [ "$distro" = "debian" ]; then
    release="${release:-bookworm}"
  elif [ "$distro" = "ubuntu" ]; then
    release="${release:-noble}"
  elif [ "$distro" = "alpine" ]; then
    release="${release:-edge}"
  else
    print_error "invalid distro selection"
    exit 1
  fi

  #install a newer debootstrap version if needed
  if [ -f "/etc/debian_version" ] && [ "$distro" = "ubuntu" -o "$distro" = "debian" ]; then
    if [ ! -f "/usr/share/debootstrap/scripts/$release" ]; then
      print_info "installing newer debootstrap version"
      mirror_url="https://deb.debian.org/debian/pool/main/d/debootstrap/"
      deb_file="$(curl "https://deb.debian.org/debian/pool/main/d/debootstrap/" | pcregrep -o1 'href="(debootstrap_.+?\.deb)"' | tail -n1)"
      deb_url="${mirror_url}${deb_file}"
      wget -q --show-progress "$deb_url" -O "/tmp/$deb_file"
      apt-get install -y "/tmp/$deb_file"
    fi
  fi

  ./build_rootfs.sh $rootfs_dir $release \
    custom_packages=$desktop_package \
    hostname=shimboot-$board \
    username=user \
    user_passwd=user \
    arch=$arch \
    distro=$distro
fi

print_title "patching $distro rootfs"
retry_cmd ./patch_rootfs.sh $shim_bin $reco_bin $rootfs_dir "quiet=$quiet"

print_title "building final disk image"
final_image="$data_dir/shimboot_$board.bin"
rm -rf $final_image
retry_cmd ./build.sh $final_image $shim_bin $rootfs_dir "quiet=$quiet" "arch=$arch" "name=$distro" "luks=$luks"
print_info "build complete! the final disk image is located at $final_image"

print_title "cleaning up"
clean_loops

if [ "$compress_img" ]; then
  image_zip="$data_dir/shimboot_$board.zip"
  print_title "compressing disk image into a zip file"
  zip -j $image_zip $final_image
  print_info "finished compressing the disk file"
  print_info "the finished zip file can be found at $image_zip" 
fi
