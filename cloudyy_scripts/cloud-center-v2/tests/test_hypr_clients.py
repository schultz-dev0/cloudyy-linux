import importlib.util
import tempfile
import unittest
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[3] / ".config/quickshell/overview/services/hypr_clients.py"
SPEC = importlib.util.spec_from_file_location("hypr_clients", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
process_app_key = MODULE.process_app_key
enrich_clients = MODULE.enrich_clients


class ProcessAppKeyTests(unittest.TestCase):
    def test_cursor_electron_bundle_resolves_cursor(self):
        self.assertEqual(process_app_key(
            "/usr/lib/electron40/electron",
            ["/usr/lib/electron40/electron", "/usr/share/cursor/resources/app/cursor.mjs"],
        ), "cursor")

    def test_native_executable_uses_its_basename(self):
        self.assertEqual(process_app_key(
            "/opt/example/example", ["/opt/example/example", "--flag"]
        ), "example")

    def test_generic_runtime_without_bundle_is_unknown(self):
        self.assertEqual(process_app_key(
            "/usr/bin/python3", ["python3", "script.py"]
        ), "")

    def test_enrichment_preserves_fields_and_ignores_missing_proc(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            proc_root = Path(temp_dir)
            pid_dir = proc_root / "42"
            pid_dir.mkdir()
            (pid_dir / "exe").symlink_to("/opt/example/example")
            (pid_dir / "cmdline").write_bytes(b"/opt/example/example\0--flag\0")
            clients = [
                {"address": "0x1", "pid": 42, "class": "Collision"},
                {"address": "0x2", "pid": 99, "class": "Collision"},
            ]

            result = enrich_clients(clients, proc_root)

            self.assertEqual(result[0]["address"], "0x1")
            self.assertEqual(result[0]["class"], "Collision")
            self.assertEqual(result[0]["processAppKey"], "example")
            self.assertNotIn("processAppKey", result[1])
            self.assertNotIn("processAppKey", clients[0])


if __name__ == "__main__":
    unittest.main()
