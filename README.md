# Chrome OS RMA Shim Bootloader

Shimboot is a collection of scripts for patching a Chrome OS RMA shim to serve as a bootloader for a standard Linux distribution. It allows you to boot a full desktop Debian install on a Chromebook, without needing to unenroll it or modify the firmware.

| <img src="/website/assets/shimboot_demo_1.jpg" alt="Shimboot (KDE) on an HP Chromebook 11 G9 EE." width="400"/> | <img src="/website/assets/shimboot_demo_2.jpg" alt="Shimboot (XFCE) on an Acer Chromebook 311 C722." width="400"/> |  
| ----- | ----- |
| Shimboot (KDE) on an HP Chromebook 11 G9 EE | Shimboot (XFCE) on an Acer Chromebook 311 C722 |

## Features:
- Run a full Debian installation on a Chromebook
- Does not modify the firmware
- Works on enterprise enrolled devices
- Can boot Chrome OS with no restrictions (useful for enrolled devices)
- Nearly full device compatibility
- Optional disk compression 
- Multiple desktop environments supported

## About:
Chrome OS RMA shims are bootable disk images which are designed to run a variety of diagnostic utilities on Chromebooks, and they'll work even if the device is enterprise enrolled. Unfortunately for Google, there exists a [security flaw](https://sh1mmer.me/) where the root filesystem of the RMA shim is not verified. This lets us replace the rootfs with anything we want, including a full Linux distribution.

Simply replacing the shim's rootfs doesn't work, as it boots in an environment friendly to the RMA shim, not regular Linux distros. To get around this, a separate bootloader is required to transition from the shim environment to the main rootfs. This bootloader then runs `pivot_root` to enter the rootfs, where it then starts the init system.

Another problem is encountered at this stage: the Chrome OS kernel will complain about systemd's mounts, and the boot process will hang. A simple workaround is to [apply a patch](https://github.com/ading2210/chromeos-systemd) to systemd, and then it can be recompiled and hosted at a [repo somewhere](https://github.com/ading2210/shimboot-repo).

After copying all the firmware from the recovery image and shim to the rootfs, we're able to boot to a mostly working XFCE desktop.

The main advantages of this approach are that you don't need to touch the device's firmware in order to run Linux. Simply rebooting and unplugging the USB drive will return the device to normal, which can be useful if the device is enterprise enrolled. However, since we are stuck with the kernel from the RMA shim, some features such as audio and suspend may not work.

### Partition Layout:
1. 1MB dummy stateful partition
2. 32MB Chrome OS kernel
3. 20MB bootloader
4. The rootfs partitions fill the rest of the disk

Note that rootfs partitions have to be named `shimboot_rootfs:<partname>` for the bootloader to recognize them.

## Status:
Driver support depends on the device you are using shimboot on. The `patch_rootfs.sh` script attempts to copy all the firmware and drivers from the shim and recovery image into the rootfs, so expect most things to work on other boards. ARM Chromebooks are not supported at the moment.

### Device Compatibility Table:
| Board Name                                       | X11               | Wifi | Speakers | Backlight | Touchscreen | 3D Accel | Bluetooth | Webcam   |
|------------------------------------------------  |-------------------|------|----------|-----------|-------------|----------|-----------|----------|
| [`dedede`](https://chrome100.dev/board/dedede)   | yes               | yes  | no       | yes       | yes         | yes      | yes       | yes      |
| [`octopus`](https://chrome100.dev/board/octopus) | yes               | yes  | yes      | yes       | yes         | yes      | yes       | yes      |
| [`nissa`](https://chrome100.dev/board/nissa)     | yes               | yes  | no       | yes       | yes         | yes      | yes       | yes      |
| [`reks`](https://chrome100.dev/board/reks)       | no<sup>[1]</sup> | yes  | untested | untested  | untested    | no       | untested  | untested |
| [`kefka`](https://chrome100.dev/board/kefka)     | no<sup>[1]</sup> | yes  | yes      | yes       | untested    | no       | untested  | untested |
| [`zork`](https://chrome100.dev/board/zork)       | yes               | yes  | no       | untested  | yes         | yes      | yes       | yes      |
| [`grunt`](https://chrome100.dev/board/grunt)     | yes               | yes  | no       | yes       | yes         | yes      | yes       | yes      |
| [`jacuzzi`](https://chrome100.dev/board/jacuzzi) | yes               | yes  | no       | yes       | untested    | no       | no        | yes      |
| [`corsola`](https://chrome100.dev/board/corsola) | yes               | yes  | untested | untested  | untested    | untested | untested  | untested |

<sup>1. The kernel is too old.</sup>

This table is incomplete. If you want to contribute a device compatibility report please create a new issue on the Github repository.

On all devices, expect the following features to work:
- Zram (compressed memory)
- Disk compression with squashfs

On all devices, the following features will not work:
- Suspend (disabled by the kernel)
- Swap (disabled by the kernel)

### TODO:
- Finish Python TUI rewrite (see the `python` branch if you want to help with this)
- Transparent disk compression
- Full disk encryption
- Support for more distros (Ubuntu and Arch maybe)
- Eliminate binwalk dependency
- Get audio to work on dedede
- Get kexec working

PRs and contributions are welcome to help implement these features.

## Usage:

### Prerequisites:
- A separate Linux PC for the build process (preferably something Debian-based)
  - WSL2 is supported if you are on Windows
  - Github Codespaces is not supported at the moment
- A USB drive that is at least 8GB in size
  - Cheap USB 2.0 drives typically won't work well due to their slow speeds
- At least 20GB of free disk space

### Video Tutorial:
[![thumbnail of the tutorial youtube video](https://img.youtube.com/vi/v327np19RXg/mqdefault.jpg)](https://www.youtube.com/watch?v=v327np19RXg)

[@blueiceyt](https://www.youtube.com/channel/UC2yMjQu-NwJSQb0tRclQMYg) made a nice [video tutorial](https://www.youtube.com/watch?v=v327np19RXg) for Shimboot. It's a lot easier to understand than the instructions on this page, and it'll cover most use cases.

### Build Instructions:
1. Find the board name of your Chromebook. You can search for the model name on [chrome100.dev](https://chrome100.dev/).
2. Clone this repository and cd into it.
3. Run `sudo ./build_complete.sh <board_name>` to download the required data and build the disk image. 

Note: If you are building for an ARM Chromebook, you need the `qemu-user-static` and `binfmt-support` packages.

[Prebuilt images](https://github.com/ading2210/shimboot/releases) are available if you don't have a suitable device to run the build on.

<details>
  <summary><b>Alternatively, you can run each of the steps manually:</b></summary>
  
  1. Grab a Chrome OS RMA Shim from somewhere. Most of them have already been leaked and aren't too difficult to find.
  2. Download a Chrome OS [recovery image](https://chromiumdash.appspot.com/serving-builds?deviceCategory=ChromeOS) for your board.
  3. Unzip the shim and the recovery image if you have not done so already.
  4. Run `mkdir -p data/rootfs` to create a directory to hold the rootfs.
  5. Run `sudo ./build_rootfs.sh data/rootfs bookworm` to build the base rootfs.
  6. Run `sudo ./patch_rootfs.sh path_to_shim path_to_reco data/rootfs` to patch the base rootfs and add any needed drivers.
  7. Run `sudo ./build.sh image.bin path_to_shim data/rootfs` to generate a disk image at `image.bin`. 
</details>

### Booting the Image:
1. Obtain a shimboot image by downloading a [prebuilt one](https://github.com/ading2210/shimboot/releases) or building it yourself. 
2. Flash the shimboot image to a USB drive or SD card. Use the [Chromebook Recovery Utility](https://chrome.google.com/webstore/detail/chromebook-recovery-utili/pocpnlppkickgojjlmhdmidojbmbodfm) or [dd](https://linux.die.net/man/1/dd) if you're on Linux.
3. Enable developer mode on your Chromebook. If the Chromebook is enrolled, follow the instructions on the [sh1mmer website](https://sh1mmer.me) (see the "Executing on Chromebook" section).
4. Plug the USB into your Chromebook and enter recovery mode. It should detect the USB and run the shimboot bootloader.
5. Boot into Debian and log in with the username and password that you configured earlier. The default username/password for the prebuilt images is `user/user`.
6. Expand the rootfs partition so that it fills up the entire disk by running `sudo expand_rootfs`.
7. Change your own password by running `passwd user`. The root user is disabled by default.

## FAQ:

#### I want to use a different Linux distribution. How can I do that?
Using any Linux distro is possible, provided that you apply the [proper patches](https://github.com/ading2210/chromeos-systemd) to systemd and recompile it. Most distros have some sort of bootstrapping tool that allows you to install it to a directory on your host PC. Then, you can just pass that rootfs directory into `patch_rootfs.sh` and `build.sh`.

Here is a list of distros that are supported out of the box:
- Debian 12
- Debian Unstable
- Alpine Linux

PRs to enable support for other distros are welcome. 

Debian Sid (the rolling release version of Debian) is also supported if you just want newer packages, and you can install it by passing an argument to `build_complete.sh`: 
```bash
sudo ./build_complete.sh dedede release=unstable
```

There is also experimental support for Alpine Linux. The Alpine disk image is about half the size compared to Debian, although some applications are missing. Pass the `distro=alpine` to use it:
```bash
sudo ./build_complete.sh dedede distro=alpine
```

#### How can I install a desktop environment other than XFCE?
You can pass the `desktop` argument to the `build_complete.sh` script, like this:
```bash
sudo ./build_complete.sh grunt desktop=lxde
```
The valid values for this argument are: `gnome`, `xfce`, `kde`, `lxde`, `gnome-flashback`, `cinnamon`, `mate`, and `lxqt`.

#### Will this prevent me from using Chrome OS normally?
Shimboot does not touch the internal storage at all, so you will be able to use Chrome OS as if nothing happened. However, if you are on an enterprise enrolled device, booting Chrome OS again will force a powerwash due to the attempted switch into developer mode.

#### Can I unplug the USB drive while using Debian?
By default, this is not possible. However, you can simply copy your Debian rootfs onto your internal storage by first using `fdisk` to repartition it, using `dd` to copy the partition, and `resize2fs` to have it take up the entire drive. In the future, loading the OS to RAM may be supported, but this isn't a priority at the moment. You can also just blindly copy the contents of your Shimboot USB to the internal storage without bothering to repartition:
```bash
#check the output of this to know what disk you're copying to and from
fdisk -l

#run this from within the shimboot bootloader
#this assumes the usb drive is on sda and internal storage is on mmcblk1
dd if=/dev/sda of=/dev/mmcblk1 bs=1M oflag=direct status=progress
```

#### GPU acceleration isn't working, how can I fix this?
If your kernel version is too old, the standard Mesa drivers will fail to load. Instead, you must download and install the `mesa-amber` drivers. Run the following commands:
```bash
sudo apt install libglx-amber0 libegl-amber0
echo "MESA_LOADER_DRIVER_OVERRIDE=i965" | sudo tee -a /etc/environment
```
You may need to change `i965` to `i915` (or `r100`/`r200` for AMD hardware), depending on what GPU you have.

For ARM Chromebooks, you may have to tweak the [Xorg configuration](https://xkcd.com/963/) instead.

#### Can the rootfs be compressed to save space?
Compressing the Debian rootfs with a squashfs is supported, and you can do this by running the regular Debian rootfs through `./build_squashfs.sh`. For example:
```bash
sudo ./build_rootfs.sh data/rootfs bookworm
sudo ./build_squashfs.sh data/rootfs_compressed data/rootfs path_to_shim
sudo ./build.sh image.bin path_to_shim data/rootfs_compressed
```
Any writes to the squashfs will persist, but they will not be compressed when saved. For the compression to be the most effective, consider pre-installing most of the software you use with `custom_packages=` before building the squashfs.

On the regular XFCE4 image, this brings the rootfs size down to 1.2GB from 3.5GB.

#### I can't connect to some wifi networks.
You may have to run these commands in order to connect to certain networks:
```
$ nmcli connection edit <your connection name>
> set 802-11-wireless-security.pmf disable
> save
> activate
```

#### Steam doesn't work.
Steam should be installed using the `sudo apt install steam` command, however it doesn't work out of the box due to security features in the shim kernel preventing the `bwrap` library from working. See [issue #12](https://github.com/ading2210/shimboot/issues/26#issuecomment-2151893062) for more info. 

To get Steam running, install and run it normally. It will fail and show a message saying that "Steam now requires user namespaces to be enabled." Run `fix_bwrap` in your terminal, relaunch Steam, and it should be working again. 

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
