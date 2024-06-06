import json
import pathlib

import utils

schemas = {}
schema_dir = utils.base_path / "config"
if utils.on_shim:
  store_dir = pathlib.Path("/mnt/state/settings")
else:
  store_dir = utils.mock_data_path / "settings"

def load_schema(schema_name):
  schema_path = schema_dir / f"{schema_name}.json"
  schema_str = schema_path.read_text()
  schema_info = json.loads(schema_str)
  schema = schema_info["schema"]

  if "extends" in schema_info:
    base_name = schema_info["extends"]
    base_schema = schemas[base_name]
    schema = base_schema | schema
  
  schemas[schema_name] = schema

def init_settings():
  schema_names = ["options", "boot_entry", "chrome_os"]
  for schema_name in schema_names:
    load_schema(schema_name)

def save_entry(key, data):
  store_dir.mkdir(exist_ok=True, parents=True)
  data_str = json.dumps(data, indent=2)
  store_path = store_dir / f"{key}.json"
  store_path.write_bytes(data_str)

init_settings()