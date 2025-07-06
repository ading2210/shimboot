#!/bin/bash
# made by HarryJarry1
rm '/home/chronos/Local State'
mv /bootloader/opt/oobeskip_state '/home/chronos/Local State'
read -p "Do you want to restart the ui now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    restart ui
fi