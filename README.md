# Chrome OS RMA Shim Bootloader

Shimboot is a collection of scripts for patching a Chrome OS RMA shim to serve as a bootloader for a standard Linux distribution. It allows you to boot a full desktop Debian install on a Chromebook, without needing to unenroll it or modify the firmware.

## About:
Chrome OS RMA shims are bootable disk images which are designed to run a variety of diagnostic utilities on Chromebooks, and they'll work even if the device is enterprise enrolled. Unfortunately for Google, there exists a [security flaw](https://sh1mmer.me/) where the root filesystem of the RMA shim is not verified. This lets us replace the rootfs with anything we want, including a full Linux distribution.

Simply replacing the shim's rootfs doesn't work, as it boots in an environment friendly to the RMA shim, not regular Linux distros. To get around this, a separate bootloader is required to transition from the shim environment to the main rootfs. This bootloader then does `pivot_root` to enter the rootfs, where it then starts the init system.

Another problem is encountered at this stage: the Chrome OS kernel will complain about systemd's mounts, and the boot process will hang. A simple workaround is to [apply a patch](https://github.com/ading2210/chromeos-systemd) to systemd, and then it can be recompiled and hosted at a [repo somewhere](https://github.com/ading2210/shimboot-repo).

After copying all the firmware from the recovery image and shim to the rootfs, we're able to boot to a mostly working XFCE desktop.

### Partition Layout:
1. 1MB dummy stateful partition
2. 32MB Chrome OS kernel
3. 20MB bootloader
4. The rootfs partitions fill the rest of the disk

Note that rootfs partitions have to be named `shimboot_rootfs:<partname>` for the bootloader to recognize them.

## Status:
Driver support depends on the device you are using shimboot on. This list is for the [`dedede`](https://chrome100.dev/board/dedede/) board, which is the only device I was able to do extensive testing on. The `patch_rootfs.sh` script attempts to copy all the firmware from the shim and recovery image into the rootfs, so expect most things to work on other boards.

### What Works:
- Booting Chrome OS
- Systemd
- X11
- XFCE
- Backlight
- Touchscreen
- 3D acceleration
- Bluetooth
- Zram
- Wifi
- Booting a squashfs
- Webcam

### What Doesn't Work:
- Audio (due to a firmware bug on `dedede`, this works just fine on `octopus`)
- Suspend (disabled by the kernel)
- Swap (disabled by the kernel)

### Development Roadmap:
- ~~build the image automatically~~
- ~~boot to a shell~~
- ~~switch_root into an actual rootfs~~
- ~~start X11 in the actual rootfs~~
- ~~ui improvements in the bootloader~~
- ~~load all needed drivers~~
- ~~autostart X11~~
- ~~host repo for patched systemd packages~~
- ~~use debootstrap to install debian~~
- ~~prompt user for hostname and account when creating the rootfs~~
- ~~auto load iwlmvm~~
- ~~get wifi fully working~~
- ~~host prebuilt images~~
- ~~write detailed documentation~~
- Finish Python TUI rewrite

### Long Term Goals:
- Transparent disk compression
- Full disk encryption
- eliminate binwalk dependency
- get audio to work
- get kexec working

## Usage:

### Prerequisites:
- A separate Linux PC for the build process (preferably something Debian-based)
- A USB that is at least 8GB in size
- At least 20GB of free disk space
- An x86-based Chromebook

### Build Instructions:
1. Find the board name of your Chromebook. You can search for the model name on [chrome100.dev](https://chrome100.dev/).
1. Clone this repository and cd into it.
2. Run `sudo ./build_complete.sh <board_name>` to download the required data and build the disk image.

Alternatively, you can run each of the steps manually:
1. Grab a Chrome OS RMA Shim from somewhere. Most of them have already been leaked and aren't too difficult to find.
2. Download a Chrome OS [recovery image](https://chromiumdash.appspot.com/serving-builds?deviceCategory=ChromeOS) for your board.
3. Unzip the shim and the recovery image if you have not done so already.
4. Run `mkdir -p data/rootfs` to create a directory to hold the rootfs.
5. Run `sudo ./build_rootfs.sh data/rootfs bookworm` to build the base rootfs.
6. Run `sudo ./patch_rootfs.sh path_to_shim path_to_reco data/rootfs` to patch the base rootfs and add any needed drivers.
7. Run `sudo ./build.sh image.bin path_to_shim data/rootfs` to generate a disk image at `image.bin`. 

### Booting the Image:
1. Obtain a shimboot image by downloading a [prebuilt one](https://github.com/ading2210/shimboot/actions?query=branch%3Amain) or building it yourself. 
2. Flash the shimboot image to a USB drive or SD card. Use the [Chromebook Recovery Utility](https://chrome.google.com/webstore/detail/chromebook-recovery-utili/pocpnlppkickgojjlmhdmidojbmbodfm) or [dd](https://linux.die.net/man/1/dd) if you're on Linux.
3. Enable developer mode on your Chromebook. If the Chromebook is enrolled, follow the instructions on the [sh1mmer website](https://sh1mmer.me) (see the "Executing on Chromebook" section).
4. Plug the USB into your Chromebook and enter recovery mode. It should detect the USB and run the shimboot bootloader.
5. Boot into Debian and log in with the username and password that you configured earlier. The default username/password for the prebuilt images is `user/user`.
6. Expand the rootfs partition so that it fills up the entire disk by running `sudo growpart /dev/sdX 4` (replacing `sdX` with the block device corresponding to your disk) to expand the partition, then running `sudo resize2fs /dev/sdX4` to expand the filesystem.
7. Change the root password and regular user password by running `sudo passwd root` and `passwd user`.

## FAQ:

#### I want to use a different Linux distribution. How can I do that?
Using any Linux distro is possible, provided that you apply the [proper patches](https://github.com/ading2210/chromeos-systemd) to systemd and recompile it. Most distros have some sort of bootstrapping tool that allows you to install it to a directory on your host PC. Then, you can just pass that rootfs dir into `build.sh`.

Debian Sid (the unstable rolling release version of Debian) is also supported if you just want newer packages, and you can install it by passing an argument to `build_rootfs.sh`: 
```bash
sudo ./build_rootfs.sh data/rootfs unstable
```
#### How can I install a desktop environment other than XFCE?
You can pass another argument to the `build_rootfs.sh` script, like this: `sudo ./build_rootfs.sh data/rootfs bookworm custom_packages=task-lxde-desktop`. The `custom_packages` argument is a list of packages (separated by spaces) that will be installed in the place of XFCE. 

#### Will this prevent me from using Chrome OS normally?
Shimboot does not touch the internal storage at all, so you will be able to use Chrome OS as if nothing happened. However, if you are on an enterprise enrolled device, booting Chrome OS again will force a powerwash due to the attempted switch into developer mode.

#### Can I unplug the USB drive while using Debian?
By default, this is not possible. However, you can simply copy your Debian rootfs onto your internal storage by first using `fdisk` to repartition it, using `dd` to copy the partition, and `resize2fs` to have it take up the entire drive. In the future, loading the OS to RAM may be supported, but this isn't a priority at the moment. You can also just blindly copy the contents of your Shimboot USB to the internal storage without bothering to repartition:
```bash
#assuming the usb drive is on sda and internal storage is on mmcblk1
sudo dd if=/dev/sda of=/dev/mmcblk1 bs=1M oflag=direct status=progress
sudo growpart /dev/mmcblk1 4
sudo resize2fs /dev/mmcblk1p4
```

#### GPU acceleration isn't working, how can I fix this?
If your kernel version is too old, the standard Mesa drivers will fail to load. Instead, you must download and install the `mesa-amber` drivers. Run the following commands:
```
sudo apt install libglx-amber0 libegl-amber0
echo "MESA_LOADER_DRIVER_OVERRIDE=i965" | sudo tee -a /etc/environment
```
You may need to change `i965` to `i915` (or `r100`/`r200` for AMD hardware), depending on what GPU you have.

#### Can the rootfs be compressed to save space?
Compressing the Debian rootfs with a squashfs is supported, and you can do this by running the regular Debian rootfs through `./build_squashfs.sh`. For example:
```bash
sudo ./build_rootfs.sh data/rootfs bookworm
sudo ./build_squashfs.sh data/rootfs_compressed data/rootfs path_to_shim
sudo ./build.sh image.bin path_to_shim data/rootfs_compressed
```
Any writes to the squashfs will persist, but they will not be compressed when saved. For the compression to be the most effective, consider pre-installing most of the software you use with `custom_packages=` before building the squashfs.

On the regular XFCE4 image, this brings the rootfs size down to 1.2GB from 3.5GB.

## Copyright:
Shimboot is licensed under the [GNU GPL v3](https://www.gnu.org/licenses/gpl-3.0.txt). Unless otherwise indicated, all code has been written by me, [ading2210](https://github.com/ading2210).

### Copyright Notice:
```
ading2210/shimboot: Boot desktop Linux from a Chrome OS RMA shim.
Copyright (C) 2023 ading2210

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```
