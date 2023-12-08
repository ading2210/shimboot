import subprocess
import pathlib
import re
import json
import utils
import os

cgpt_path = "/sbin/cgpt"

if not utils.on_shim:
  mock_disks_path = utils.mock_data_path / "disks"
  mock_disks_text = (mock_disks_path / "disks.json").read_text()
  mock_disks = json.loads(mock_disks_text) 

#find the root of the bootloader by parsing dmesg
def find_root():
  if utils.on_shim:
    dmesg = utils.run_command("dmesg")
  else:
    dmesg = (utils.mock_data_path / "dmesg" / "dmesg.txt").read_text()
  
  root_regex = r'EXT4-fs \((.+?)\): mounting ext2'
  ext2_partitions = re.findall(root_regex, dmesg)
  return "/dev/" + ext2_partitions[0]

#find the bootloader stateful for persisting settings
def find_state():
  if not utils.on_shim:
    return "/dev/sda1" #for testing

  root_part = find_root()
  disk = disk_from_part(root_part)
  return get_part_dev(disk, 1)

#get disk disk from partition device
def disk_from_part(part_device):
  dev_name = pathlib.Path(part_device).name
  part_link = pathlib.Path("/sys/class/block/") / dev_name
  link_dest = part_link.readlink()
  disk_name = link_dest.parent.name
  return "/dev/" + disk_name

#get all physical disks on the system
def get_disks():
  if not utils.on_shim:
    return list(mock_disks.keys())

  disks = []
  for path in pathlib.Path("/sys/block").iterdir():
    disk_device = pathlib.Path("/dev") / path.name
    if path.name.startswith(("loop", "zram")):
      continue
    if not disk_device.exists():
      continue
    disks.append(str(disk_device))
  return disks

#partition device from disk and part number
def get_part_dev(disk, part_num):
  if disk[-1].isdigit():
    return f"{disk}p{part_num}"
  else:
    return f"{disk}{part_num}"

#get all partitions on a particular disk
def get_partitions(disk):
  try:
    if utils.on_shim:
      output = utils.run_command([cgpt_path, "show", disk, "-v"])
    else:
      output = pathlib.Path(mock_disks_path / mock_disks[disk]).read_text()
  except subprocess.CalledProcessError:
    return []
  
  partitions_output = re.findall(r'Pri GPT table\n(.+)\n.+Sec GPT table', output, flags=re.S)[0]
  partition_data = re.findall(r'\s+\d+\s+\d+\s+(\d+)\s+Label: "(.*?)"', partitions_output)
  partition_details = re.split(r'\s+\d+\s+\d+\s+\d+.+', partitions_output)
  partition_details = list(filter(None, partition_details))

  partitions = []
  for part_num, part_label in partition_data:
    part_details_str = partition_details[int(part_num)-1]
    part_type = re.findall(r'Type: (.+)', part_details_str)[0]
    part_uuid = re.findall(r'UUID: (.+)', part_details_str)[0]
    part_device = get_part_dev(disk, part_num)

    partitions.append({
      "disk": disk,
      "device": part_device,
      "num": int(part_num),
      "label": part_label,
      "type": part_type,
      "uuid": part_uuid,
    })

  return partitions

def get_valid_partitions(disk):
  partitions = get_partitions(disk)
  valid_partitions = []

  for partition in partitions:
    if partition["type"] == "ChromeOS rootfs" and partition["label"] in ["ROOT-A", "ROOT-B"]:
      partition["name"] = partition["label"]
      valid_partitions.append(partition)
      
    elif partition["label"].startswith("shimboot_rootfs:"):
      partition["name"] = partition["label"].replace("shimboot_rootfs:", "", 1)
      valid_partitions.append(partition)

  return valid_partitions

def get_all_partitions():
  disks = get_disks()
  all_partitions = []

  for disk in disks:
    partitions = get_valid_partitions(disk)
    all_partitions += partitions
  
  return all_partitions

#some test code, this file will never be called as main normally 
if __name__ == "__main__":
  state = find_state()
  print(state)