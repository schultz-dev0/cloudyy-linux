import unittest
from pathlib import Path
from unittest import mock

from lib import hcm_lua


class TestAtomicWrite(unittest.TestCase):
    def test_atomic_write_creates_file(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/hcm_lua_test")):
            target = hcm_lua.HYPR_DIR / "sub" / "a.lua"
            hcm_lua.atomic_write(target, "hello\n")
            self.assertEqual(target.read_text(), "hello\n")
            self.assertFalse(target.with_suffix(".lua.tmp").exists())
            target.unlink()
            target.parent.rmdir()
            target.parent.parent.rmdir()

    def test_atomic_write_replaces_existing(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/hcm_lua_test2")):
            target = hcm_lua.HYPR_DIR / "a.lua"
            hcm_lua.atomic_write(target, "old\n")
            hcm_lua.atomic_write(target, "new\n")
            self.assertEqual(target.read_text(), "new\n")
            target.unlink()
            target.parent.rmdir()


class TestResetToDefault(unittest.TestCase):
    def test_reset_copies_default_over_live_file(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/hcm_reset_test")), \
             mock.patch.object(hcm_lua, "DEFAULTS_DIR", Path("/tmp/hcm_reset_defaults")):
            hcm_lua.DEFAULTS_DIR.mkdir(parents=True, exist_ok=True)
            (hcm_lua.DEFAULTS_DIR / "bindings.lua").write_text("-- shipped default\n")
            hcm_lua.HYPR_DIR.mkdir(parents=True, exist_ok=True)
            (hcm_lua.HYPR_DIR / "bindings.lua").write_text("-- user's edited version\n")

            ok, message = hcm_lua.reset_to_default("bindings")

            self.assertTrue(ok)
            self.assertEqual((hcm_lua.HYPR_DIR / "bindings.lua").read_text(), "-- shipped default\n")
            (hcm_lua.HYPR_DIR / "bindings.lua").unlink()
            hcm_lua.HYPR_DIR.rmdir()
            (hcm_lua.DEFAULTS_DIR / "bindings.lua").unlink()
            hcm_lua.DEFAULTS_DIR.rmdir()

    def test_reset_missing_default_reports_failure(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/hcm_reset_test3")), \
             mock.patch.object(hcm_lua, "DEFAULTS_DIR", Path("/tmp/hcm_reset_defaults_missing")):
            ok, message = hcm_lua.reset_to_default("nonexistent")
            self.assertFalse(ok)
            self.assertIn("No shipped default", message)


class TestScanModules(unittest.TestCase):
    def test_scan_lists_all_present_modules(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/hcm_scan_test")):
            hcm_lua.HYPR_DIR.mkdir(parents=True, exist_ok=True)
            (hcm_lua.HYPR_DIR / "bindings.lua").write_text("-- @description = Keybindings\n")
            modules = hcm_lua.scan_modules()
            names = {m.filename for m in modules}
            self.assertIn("bindings.lua", names)
            bindings = next(m for m in modules if m.filename == "bindings.lua")
            self.assertEqual(bindings.description, "Keybindings")
            self.assertFalse(hasattr(bindings, "status"))
            (hcm_lua.HYPR_DIR / "bindings.lua").unlink()
            hcm_lua.HYPR_DIR.rmdir()


if __name__ == "__main__":
    unittest.main()
