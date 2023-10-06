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
2. Download a Devuan live ISO. Run it inside a VM and install it to a disk image. Mount the disk image in the host.
3. Run `sudo DEBUG=1 ./build.sh`. The `rootfs_dir` argument should point to where you mounted the rootfs in part 2.
4. Flash the generated image to a USB drive or SD card.