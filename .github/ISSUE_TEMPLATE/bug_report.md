---
name: Bug report
about: Create a report to help us improve
title: ''
labels: bug
assignees: ''

---

<!--
Important: Please do not delete this issue template!

Before making a bug report please check that:
- The USB drive/SD card you are using isn't faulty
  - Dirt cheap USB 2.0 drives or fake high capacity ones will not work
  - Generally if your drive is unbranded it is slow and of poor quality
- The disk image you are using is not corrupted
- You have *some* knowledge on how to use Linux
-->

**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Expected behavior**
A clear and concise description of what you expected to happen.

**Screenshots / Photos**
If applicable, add screenshots or photos to help explain your problem.

If you are reporting an issue with the build process, please run the scripts in debug mode by putting `DEBUG=1` before the build commmand, like `sudo DEBUG=1 ./build_complete.sh`.

**Target Chrome OS Device (please complete the following information):**
 - Board Name (e.g. dedede)
 - Device Name (e.g. drawcia) <!-- this page has a list of them: https://chromiumdash.appspot.com/serving-builds -->
 - Shimboot version (e.g. v1.0.1) 

<!-- If you are using a prebuilt image please make note of that and delete this section. -->
<!-- This section is for the device you build shimboot on, not your chromebook. -->
**Build Device (please complete the following information):**
 - OS: [e.g. Debian 12]
 - Neofetch out [run `neofetch --stdout` and paste it here]

**Additional context**
Add any other context about the problem here.
