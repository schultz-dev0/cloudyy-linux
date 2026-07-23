import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import lib.hcm_lua as hcm_lua
import lib.keybind_manager_lua as kbm
from lib.ccd import keybinds

# A distro bindings.lua written in this project's real multi-line hl.bind()
# style — the format that scan_keybinds() used to silently fail to parse.
DISTRO_BINDINGS = """local mainMod = "SUPER"

hl.bind(
\tmainMod .. " + Q",
\thl.dsp.window.close(),
\t{ desc = "Close window" }
)
hl.bind(
\t"ALT + 1",
\thl.dsp.exec_cmd("firefox"),
\t{ desc = "Browser" }
)
"""


class KeybindsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        hypr_dir = Path(self.tmp.name)
        (hypr_dir / "source").mkdir()
        (hypr_dir / "user-configs").mkdir()

        source_bindings = hypr_dir / "source" / "bindings.lua"
        source_bindings.write_text(DISTRO_BINDINGS)
        user_bindings = hypr_dir / "user-configs" / "user_bindings.lua"
        main_lua = hypr_dir / "hyprland.lua"  # deliberately absent -> hcm scan skipped

        for name, value in [
            ("SOURCE_BINDINGS_LUA", source_bindings),
            ("BINDINGS_LUA", user_bindings),
            ("MAIN_LUA", main_lua),
        ]:
            p = mock.patch.object(kbm, name, value)
            p.start()
            self.addCleanup(p.stop)

        # _ensure_user_bindings_lua() shells out to the real `hcm` binary via
        # hcm_lua.switch_to_user_override() to "activate" a user override —
        # that binary/its expectations of ~/.config/hypr are out of scope for
        # a unit test, so replace it with the same copy-then-mark-active
        # behavior in pure Python.
        def fake_switch_to_user_override(cf):
            shutil.copy(source_bindings, user_bindings)
            return hcm_lua.UserOverrideResult(
                edit_path=user_bindings, activated=True, message="ok"
            )

        switch_patch = mock.patch.object(
            hcm_lua, "switch_to_user_override", side_effect=fake_switch_to_user_override
        )
        switch_patch.start()
        self.addCleanup(switch_patch.stop)

        # keybinds.save_keybind/delete_keybind call `hyprctl reload` after a
        # successful write — patch just that name, not the whole subprocess
        # module, so hcm_json (if it were ever hit) isn't silently mocked too.
        reload_patch = mock.patch.object(keybinds.subprocess, "run")
        self.reload_mock = reload_patch.start()
        self.addCleanup(reload_patch.stop)


class TestListKeybinds(KeybindsTest):
    def test_parses_multiline_distro_binds(self):
        result = keybinds.list_keybinds({})
        combos = {kb["keys"] for kb in result["keybinds"]}
        self.assertEqual(combos, {"SUPER + Q", "ALT + 1"})  # "mainMod .. ..." resolved
        self.assertTrue(any("firefox" in kb["dispatcher"] for kb in result["keybinds"]))
        self.assertEqual(len(result["keybinds"]), 2)
        self.assertTrue(all(not kb["owned"] for kb in result["keybinds"]))

    def test_categories_present(self):
        result = keybinds.list_keybinds({})
        ids = {c["id"] for c in result["categories"]}
        self.assertEqual(ids, {"workspace", "window", "app", "other"})

    def test_categorizes_exec_cmd_as_app(self):
        result = keybinds.list_keybinds({})
        firefox = next(kb for kb in result["keybinds"] if "firefox" in kb["dispatcher"])
        self.assertEqual(firefox["category"], "app")


class TestSaveKeybind(KeybindsTest):
    def test_add_new_keybind(self):
        result = keybinds.save_keybind({
            "keys": "SUPER + T",
            "dispatcher": 'hl.dsp.exec_cmd("kitty")',
            "opts": '{ desc = "Terminal" }',
        })
        self.assertTrue(result["ok"])
        self.reload_mock.assert_called_once_with(["hyprctl", "reload"], check=False)

        listed = keybinds.list_keybinds({})
        added = [kb for kb in listed["keybinds"] if kb["keys"] == "SUPER + T"]
        self.assertEqual(len(added), 1)
        self.assertTrue(added[0]["owned"])

    def test_missing_keys_or_dispatcher_rejected(self):
        result = keybinds.save_keybind({"keys": "", "dispatcher": "hl.dsp.window.close()"})
        self.assertFalse(result["ok"])
        self.reload_mock.assert_not_called()

    def test_update_owned_keybind_in_place(self):
        keybinds.save_keybind({"keys": "SUPER + T", "dispatcher": 'hl.dsp.exec_cmd("kitty")'})
        self.reload_mock.reset_mock()

        result = keybinds.save_keybind({
            "old_keys": "SUPER + T",
            "old_dispatcher": 'hl.dsp.exec_cmd("kitty")',
            "was_owned": True,
            "keys": "SUPER + T",
            "dispatcher": 'hl.dsp.exec_cmd("alacritty")',
        })
        self.assertTrue(result["ok"])
        listed = keybinds.list_keybinds({})
        owned = [kb for kb in listed["keybinds"] if kb["owned"]]
        self.assertEqual(len(owned), 1)
        self.assertIn("alacritty", owned[0]["dispatcher"])

    def test_adopt_locked_keybind_leaves_original_untouched(self):
        result = keybinds.save_keybind({
            "old_keys": 'mainMod .. " + Q"',
            "old_dispatcher": "hl.dsp.window.close()",
            "was_owned": False,
            "keys": "SUPER + Q",
            "dispatcher": "hl.dsp.window.kill()",
        })
        self.assertTrue(result["ok"])
        listed = keybinds.list_keybinds({})
        locked_close = [kb for kb in listed["keybinds"]
                        if not kb["owned"] and "close" in kb["dispatcher"]]
        owned_kill = [kb for kb in listed["keybinds"]
                      if kb["owned"] and "kill" in kb["dispatcher"]]
        self.assertEqual(len(locked_close), 1)   # original distro bind untouched
        self.assertEqual(len(owned_kill), 1)     # new override added


class TestDeleteKeybind(KeybindsTest):
    def test_delete_owned_keybind(self):
        keybinds.save_keybind({"keys": "SUPER + T", "dispatcher": 'hl.dsp.exec_cmd("kitty")'})
        self.reload_mock.reset_mock()

        result = keybinds.delete_keybind({
            "keys": "SUPER + T", "dispatcher": 'hl.dsp.exec_cmd("kitty")',
        })
        self.assertTrue(result["ok"])
        self.reload_mock.assert_called_once()
        listed = keybinds.list_keybinds({})
        self.assertEqual([kb for kb in listed["keybinds"] if kb["owned"]], [])

    def test_delete_nonexistent_keybind_fails_gracefully(self):
        result = keybinds.delete_keybind({
            "keys": "SUPER + Z", "dispatcher": "hl.dsp.nothing()",
        })
        self.assertFalse(result["ok"])
        self.reload_mock.assert_not_called()


if __name__ == "__main__":
    unittest.main()
