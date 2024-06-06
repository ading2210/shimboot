import json

import utils

schema_dir = utils.base_path / "config"
schemas = {}

def load_schema(schema_name):
  schema_path = schema_dir / (schema_name + ".json")
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

init_settings()