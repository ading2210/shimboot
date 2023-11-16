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
    if path.name.startswith(("loop", "zram")):
      continue
    disks.append(str(path.name))
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
    return None
  
  partitions_output = re.findall(r'Pri GPT table\n(.+)\n.+Sec GPT table', output, flags=re.S)[0]
  partition_data = re.findall(r'\s+\d+\s+\d+\s+(\d+)\s+Label: "(.*?)"', partitions_output)
  partition_details = re.split(r'\s+\d+\s+\d+\s+\d+.+', partitions_output)
  partition_details = list(filter(None, partition_details))

  partitions = []
  for part_num, part_label in partition_data:
    part_details_str = partition_details[int(part_num)-1]
    part_type = re.findall(r'Type: (.+)', part_details_str)[0]
    part_uuid = re.findall(r'UUID: (.+)', part_details_str)[0]

    partitions.append({
      "num": int(part_num),
      "label": part_label,
      "type": part_type,
      "uuid": part_uuid
    })

  return partitions

if __name__ == "__main__":
  print(get_disks())
  print(json.dumps(get_partitions("/dev/sda"), indent=2))