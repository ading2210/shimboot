import subprocess
import pathlib
import re
import json
import utils

cgpt_path = "/sbin/cgpt"

if not utils.on_shim:
  mock_disks_path = utils.mock_data_path / "disks"
  mock_disks_text = (mock_disks_path / "disks.json").read_text()
  mock_disks = json.loads(mock_disks_text) 

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

#get all partitions on a particular disk
def get_partitions(disk):
  try:
    if utils.on_shim:
      output_bytes = subprocess.check_output([cgpt_path, "show", disk, "-v"], stderr=subprocess.DEVNULL)
      output = output_bytes.decode()
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
    
    if disk[-1].isdigit():
      part_device = f"{disk}p{part_num}"
    else:
      part_device = f"{disk}{part_num}"

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
      

if __name__ == "__main__":
  print(json.dumps(get_all_partitions(), indent=2))