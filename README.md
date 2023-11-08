# Chrome OS RMA Shim Bootloader

Shimboot is a collection of scripts for patching a Chrome OS RMA shim to serve as a bootloader for a standard Linux distribution. It allows you to boot a full desktop Debian install on a Chromebook, without needing to unenroll it or modify the firmware.

## About:
Chrome OS RMA shims are bootable disk images which are designed to run a variety of diagnostic utilities on Chromebooks, and they'll work even if the device is enterprise enrolled. Unfortunately for Google, there exists a [security flaw](https://sh1mmer.me/) where the root filesystem of the RMA shim is not verified. This lets us replace the rootfs with anything we want, including a full Linux distribution.

Simply replacing the shim's rootfs doesn't work, as it boots in an environment friendly to the RMA shim, not regular Linux distros. To get around this, a separate bootloader is required to transition from the shim environment to the main rootfs. This bootloader then does `pivot_root` to enter the rootfs, where it then starts the init system.

Another problem is encountered at this stage: the Chrome OS kernel will complain about systemd's mounts, and the boot process will hang. A simple workaround is to [apply a patch](https://github.com/ading2210/chromeos-systemd) to systemd, and then it can be recompiled and hosted at a [repo somewhere](https://shimboot.ading.dev/debian/).

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
- Wifi (partially)
- Suspend (partially)

### What Doesn't Work:
- Audio

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
- get wifi fully working
- ~~host prebuilt images~~
- ~~write detailed documentation~~

### Long Term Goals:
- eliminate binwalk dependency
- get audio to work

## Usage:

### Prerequisites:
- A separate Linux PC for the build process (preferably something Debian-based)
- A USB that is at least 8GB in size
- At least 20GB of free disk space
- An x86-based Chromebook

### Build Instructions:
1. Grab a Chrome OS RMA Shim from somewhere. Most of them have already been leaked and aren't too difficult to find.
2. Download a Chrome OS [recovery image](https://chromiumdash.appspot.com/serving-builds?deviceCategory=ChromeOS) for your board.
3. Clone this repository and cd into it.
4. Run `mkdir -p data/rootfs` to create a directory to hold the rootfs.
5. Run `sudo ./build_rootfs.sh data/rootfs bookworm` to build the base rootfs.
6. Run `sudo ./patch_rootfs.sh path_to_shim path_to_reco data/rootfs` to patch the base rootfs and add any needed drivers.
7. Run `sudo ./build.sh image.bin path_to_shim data/rootfs` to generate a disk image at `image.bin`. 

### Booting the Image:
1. Obtain a shimboot image by downloading a [prebuilt one](https://dl.ading.dev/shimboot/) or building it yourself. 
2. Flash the shimboot image to a USB drive or SD card. Use the [Chromebook Recovery Utility](https://chrome.google.com/webstore/detail/chromebook-recovery-utili/pocpnlppkickgojjlmhdmidojbmbodfm) or [dd](https://linux.die.net/man/1/dd) if you're on Linux.
3. Enable developer mode on your Chromebook. If the Chromebook is enrolled, follow the instructions on the [sh1mmer website](https://sh1mmer.me) (see the "Executing on Chromebook" section).
4. Plug the USB into your Chromebook and enter recovery mode. It should detect the USB and run the shimboot bootloader.
5. Boot into Debian and log in with the username and password that you configured earlier. The default username/password for the prebuilt images is `user/user`.
6. Expand the rootfs partition so that it fills up the entire disk by running `sudo growpart /dev/sdX 4` (replacing `sdX` with the block device corresponding to your disk) to expand the partition, then running `sudo resize2fs /dev/sdX` to expand the filesystem.

## FAQ:

#### I want to use a different Linux distribution. How can I do that?
Using any Linux distro is possible, provided that you apply the [proper patches](https://github.com/ading2210/chromeos-systemd) to systemd and recompile it. Most distros have some sort of bootstrapping tool that allows you to install it to a directory on your host PC. Then, you can just pass that rootfs dir into `build.sh`.

#### How can I install a desktop environment other than XFCE?
Simply edit `rootfs/opt/setup_rootfs.sh`, and change the line after the `#install desktop` comment. By default, this is set to install XFCE using the `task-xfce-desktop` package, but you can change this to install whatever you want.

#### Will this prevent me from using Chrome OS normally?
Shimboot does not touch the internal storage at all, so you will be able to use Chrome OS as if nothing happened. However, if you are on an enterprise enrolled device, booting Chrome OS again will force a powerwash due to the attempted switch into developer mode.

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
