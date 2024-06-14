---
name: Device Compatibility Report
about: Report your experiences using Shimboot on a previously untested device.
title: 'Device compatibility report for: (device name)'
labels: documentation
assignees: ''

---

This template is not meant to be used if Shimboot fails completely. Submit a bug report instead.

**Compatibility Info**:
- Board Name: (e.g. octopus)
- X11: yes/no/untested  <!-- X11 is what handles your system's GUI. If a desktop showed up at all then X11 worked. -->
- Wifi: yes/no/untested 
- Internal Audio: yes/no/untested <!-- This is referring to your laptop speakers. -->
- Backlight: yes/no/untested  <!-- This means whether or not you can control your screen brightness. -->
- Touchscreen: yes/no/untested
- 3D acceleration: yes/no/untested <!-- Does `glxinfo | grep "renderer string"` report the correct GPU name? -->
- Bluetooth: yes/no/untested
- Webcam: yes/no/untested


**Other Notes:**: