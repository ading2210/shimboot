#!/bin/bash

#build a rootfs that uses a squashfs + unionfs
#consists of a minimal busybox system containing:
# - FUSE kernel modules from the shim
# - unionfs-fuse statically compiled 
# - the main squashfs, compressed with gzip


#todo - gotta refactor the other build scripts first