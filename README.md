# Chrome OS RMA Shim Bootloader

This is a set of scripts for patching a Chrome OS RMA shim to serve as a bootloader for a standard Linux disto.

## Current Development Roadmap:
- ~~build the image automatically~~
- ~~boot to a shell~~
- ~~switch_root into an actual rootfs~~
- ~~start X11 in the actual rootfs~~
- ~~ui improvements in the bootloader~~
- load all needed drivers
- autostart X11

## Usage:
1. Grab a Chrome OS RMA Shim from somewhere. Most of them have already been leaked and aren't too difficult to find.
2. Download a [Devuan live ISO](https://www.devuan.org/get-devuan). Run it inside a VM and install it to a disk image. Mount the disk image in the host. (Use `losetup -P` for this.)
3. Run `sudo DEBUG=1 ./build.sh`. The `rootfs_dir` argument should point to where you mounted the rootfs in part 2.
4. Flash the generated image to a USB drive or SD card.

## License:
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