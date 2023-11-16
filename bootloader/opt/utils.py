import pathlib

#define a few useful paths
on_shim = pathlib.Path("/sbin/frecon-lite").exists()
base_path = pathlib.Path(__file__).resolve().parent
mock_data_path = base_path / "mock_data"