# Chrome OS RMA Shim Bootloader

This is a set of scripts for patching a Chrome OS RMA shim to serve as a bootloader for a standard Linux disto.

## Current Development Roadmap:
- ~~build the image automatically~~
- ~~boot to a shell~~
- ~~switch_root into an actual rootfs~~
- ~~start X11 in the actual rootfs~~
- ~~ui improvements in the bootloader~~
- ~~load all needed drivers~~
- ~~autostart X11~~
- ~~host repo for patched systemd packages~~
- ~~use debootstrap to install debian~~

## Usage:
1. Grab a Chrome OS RMA Shim from somewhere. Most of them have already been leaked and aren't too difficult to find.
2. Download a Chrome OS [recovery image](https://chromiumdash.appspot.com/serving-builds?deviceCategory=ChromeOS) for your board.
3. Clone this repository and cd into it.
4. Run `mkdir -P data/rootfs` to make a directory for the rootfs.
5. Run `sudo ./build_rootfs.sh data/rootfs bookworm` to build the base rootfs.
6. Run `sudo ./patch_rootfs.sh path_to_shim path_to_reco data/rootfs` to build the base rootfs.
7. Run `sudo ./build.sh image.bin path_to_shim data/rootfs`. This will generate a disk image at image.bin. 
8. Flash the generated image to a USB drive or SD card.

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