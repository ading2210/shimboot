import pathlib

#define a few useful paths
on_shim = pathlib.Path("/bin/bootstrap.sh").exists()
base_path = pathlib.Path(__file__).resolve().parent
mock_data_path = base_path / "mock_data"
output_file = pathlib.Path("/tmp/bootloader_result")