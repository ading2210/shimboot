#!/bin/bash

. ./common.sh
. ./image_utils.sh

# TO DO:
# Go To Sleep
# Todo list created on 22.03.2025 23:10.

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
  echo "  distro       - The Linux distro to use. This should be either 'debian', 'ubuntu', or 'alpine'."
  echo "  display_manager - The Display Manager to use valid options are: "
  # Lightdm may be Broken! And Only for Ubuntu At this time of Being
  # LXDM is giving one error but its working!
  echo "                    sddm, lightdm-gtk, lxdm"
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
display_manager="${args['display_manager']-lightdm-gtk}"

# Validate display_manager type
valid_display_managers=("sddm" "lightdm-gtk" "lxdm")

if [[ ! " ${valid_display_managers[@]} " =~ " ${display_manager} " ]]; then
  echo "Wrong display manager type, correct one and try again. Valid options are: sddm, lightdm-gtk, lxdm."
  exit 1
fi

# Check for distro and display_manager
if [[ "$distro" == "debian" || "$distro" == "alpine" ]]; then
  echo "Sorry, you must choose Ubuntu to choose a display manager."
  exit 1
fi

if [[ "$distro" == "ubuntu" && -z "$display_manager" ]]; then
  echo "Please add a display manager from the list in --help"
  exit 1
fi

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

kernel_arch="$(uname -m)"
host_arch="unknown"
if [ "$kernel_arch" = "x86_64" ]; then
  host_arch="amd64"
elif [ "$kernel_arch" = "aarch64" ]; then
  host_arch="arm64"
fi

needed_deps="wget python3 unzip zip git debootstrap cpio binwalk pcregrep cgpt mkfs.ext4 mkfs.ext2 fdisk depmod findmnt lz4 pv"
if [ "$(check_deps "$needed_deps")" ]; then
  #install deps automatically on debian and ubuntu
  if [ -f "/etc/debian_version" ]; then
    print_title "attempting to install build deps"
    apt-get install wget python3 unzip zip debootstrap cpio binwalk pcregrep cgpt kmod pv lz4 -y
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

shim_url="https://ddl.kxtz.dev/api/v1/download?path=/ChromeOS/shims/Raw/$board.zip"
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
    print_info "extracting $zip_path"
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

print_title "downloading recovery image"
download_and_unzip $reco_url $reco_zip $reco_bin

print_title "downloading shim image"
download_and_unzip $shim_url $shim_zip $shim_bin

print_title "building $distro rootfs"
if [ ! "$rootfs_dir" ]; then
  # Include the selected display_manager package along with the desktop package
  display_manager_package="${display_manager}"
  desktop_package="task-$desktop-desktop"
  
  # Root filesystem directory setup
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
    # Add the selected display_manager to the package list for Ubuntu
    desktop_package="$desktop_package $display_manager_package"
  elif [ "$distro" = "alpine" ]; then
    release="${release:-edge}"
  else
    print_error "invalid distro selection"
    exit 1
  fi

  ./build_rootfs.sh $rootfs_dir $release \
    custom_packages="$desktop_package" \
    hostname=shimboot-$board \
    username=user \
    user_passwd=user \
    arch=$arch \
    distro=$distro
fi

# Add the section to remove the default display manager and install the selected one
print_title "removing default display manager"

# Remove the default display manager if it's Ubuntu
if [ "$distro" = "ubuntu" ]; then
  current_dm=$(cat /etc/X11/default-display-manager)
  if [ -n "$current_dm" ]; then
    print_info "Removing current display manager: $current_dm"
    sudo apt-get remove --purge -y "$current_dm"
  fi

  # Install the chosen display_manager
  print_title "installing selected display manager ($display_manager)"
  case "$display_manager" in
    sddm)
      sudo apt-get install -y sddm
      ;;
    lightdm-gtk)
      sudo apt-get install -y lightdm-gtk-greeter
      ;;
    lxdm)
      sudo apt-get install -y lxdm
      ;;
    *)
      print_error "Invalid display manager type: $display_manager"
      exit 1
      ;;
  esac

  # Optionally, set the new display manager to be the default
  sudo dpkg-reconfigure "$display_manager"
  print_info "$display_manager has been installed and set as the default display manager."
fi

print_title "patching $distro rootfs"
retry_cmd ./patch_rootfs.sh $shim_bin $reco_bin $rootfs_dir "quiet=$quiet"

print_title "building final disk image"
final_image="$data_dir/shimboot_$board.bin"
rm -rf $final_image
retry_cmd ./build.sh $final_image $shim_bin $rootfs_dir "quiet=$quiet" "arch=$arch" "name=$distro"
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
