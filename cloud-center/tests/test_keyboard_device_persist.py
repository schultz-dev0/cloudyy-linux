import unittest
from pathlib import Path
from unittest import mock

from lib import hcm_lua, keyboard_device_persist as kbd


class TestPersist(unittest.TestCase):
    def test_disabling_writes_managed_block(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/kbd_persist_test1")):
            path = hcm_lua.HYPR_DIR / "input.lua"
            self.addCleanup(lambda: path.exists() and (path.unlink(), path.parent.rmdir()))

            with mock.patch.object(kbd, "_hyprctl_eval_ok", return_value=True), \
                 mock.patch.object(kbd.subprocess, "run") as run_mock:
                enabled = kbd.set_keyboard_enabled(False)

            self.assertIs(enabled, False)
            text = path.read_text(encoding="utf-8")
            self.assertIn(kbd._BEGIN, text)
            self.assertIn('name = "at-translated-set-2-keyboard"', text)
            self.assertIn("enabled = false,", text)
            self.assertIn(kbd._END, text)
            run_mock.assert_not_called()

    def test_enabling_clears_managed_block(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/kbd_persist_test2")):
            path = hcm_lua.HYPR_DIR / "input.lua"
            self.addCleanup(lambda: path.exists() and (path.unlink(), path.parent.rmdir()))

            with mock.patch.object(kbd, "_hyprctl_eval_ok", return_value=True):
                kbd.set_keyboard_enabled(False)
                kbd.set_keyboard_enabled(True)

            text = path.read_text(encoding="utf-8")
            self.assertIn(f"{kbd._BEGIN}\n{kbd._END}", text)
            self.assertNotIn("enabled = false,", text)

    def test_preserves_surrounding_content(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/kbd_persist_test3")):
            path = hcm_lua.HYPR_DIR / "input.lua"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("-- untouched line\nhl.config({ input = {} })\n", encoding="utf-8")
            self.addCleanup(lambda: path.exists() and (path.unlink(), path.parent.rmdir()))

            with mock.patch.object(kbd, "_hyprctl_eval_ok", return_value=True):
                kbd.set_keyboard_enabled(False)

            text = path.read_text(encoding="utf-8")
            self.assertIn("-- untouched line", text)
            self.assertIn("hl.config({ input = {} })", text)

    def test_apply_falls_back_to_reload_on_eval_failure(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/kbd_persist_test4")):
            path = hcm_lua.HYPR_DIR / "input.lua"
            self.addCleanup(lambda: path.exists() and (path.unlink(), path.parent.rmdir()))

            with mock.patch.object(kbd, "_hyprctl_eval_ok", return_value=False), \
                 mock.patch.object(kbd.subprocess, "run") as run_mock:
                kbd.set_keyboard_enabled(False)

            run_mock.assert_called_once_with(["hyprctl", "reload"], capture_output=True)


if __name__ == "__main__":
    unittest.main()
