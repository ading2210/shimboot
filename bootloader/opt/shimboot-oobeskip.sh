#!/bin/bash
# made by HarryJarry1
echo "Welcome to oobeskip for shimboot"
echo "This script allows you to skip the oobe, and get into a temporary unenrolled environment without needing to actually unenroll."
rm '/home/chronos/Local State'
cp /bootloader/opt/oobeskip_state '/home/chronos/Local State'
read -p "Do you want to restart the ui now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    restart ui
fi
