#!/bin/bash
# made by HarryJarry1
cd /home/chronos
rm '/home/chronos/Local State'
mv /bootloader/oobeskip_state '/home/chronos/Local State'
echo "Please reboot your device for changes to take effect"
sleep 5