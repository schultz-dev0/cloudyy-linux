import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from lib import rules_startup_page as legacy


class FakeRulesModule:
    WindowRule = legacy.WindowRule
    LayerRule = legacy.LayerRule
    AutostartEntry = legacy.AutostartEntry
    EnvVar = legacy.EnvVar

    MANAGED_STATE_PREFIX = legacy.MANAGED_STATE_PREFIX

    _parse_conf = staticmethod(legacy._parse_conf)
    _parse_window_rules = staticmethod(legacy._parse_window_rules)
    _parse_layer_rules = staticmethod(legacy._parse_layer_rules)
    _parse_autostart = staticmethod(legacy._parse_autostart)
    _parse_env_vars = staticmethod(legacy._parse_env_vars)
    _dataclass_window_rules = staticmethod(legacy._dataclass_window_rules)
    _dataclass_layer_rules = staticmethod(legacy._dataclass_layer_rules)
    _dataclass_autostart = staticmethod(legacy._dataclass_autostart)
    _dataclass_env_vars = staticmethod(legacy._dataclass_env_vars)
    _render_window_rules_lua = staticmethod(legacy._render_window_rules_lua)
    _render_layer_rules_lua = staticmethod(legacy._render_layer_rules_lua)


class RulesSessionTest(unittest.TestCase):
    def setUp(self):
        from lib import hcm_lua
        from lib.ccd import rules_startup

        self.backend = rules_startup
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        defaults = root / "defaults"
        defaults.mkdir()

        # Post-refactor there's one live file per surface (no source/ vs
        # user-configs/ split); "distro" content instead lives at the
        # tracked seed path, hcm_lua.DEFAULTS_DIR/<surface>.lua.
        self.paths = {
            "windowrules": root / "windowrules.lua",
            "autostart": root / "autostart.lua",
            "variables": root / "variables.lua",
        }
        (defaults / "windowrules.lua").write_text(
            'hl.window_rule({ name = "distro", match = { class = "^(base)$" }, float = true })\n'
        )
        (defaults / "autostart.lua").write_text('hl.exec_once("distro-daemon")\n')
        (defaults / "variables.lua").write_text('hl.env("TERMINAL", "kitty")\n')

        distro_defaults_patch = mock.patch.object(hcm_lua, "DEFAULTS_DIR", defaults)
        distro_defaults_patch.start()
        self.addCleanup(distro_defaults_patch.stop)

        state = {
            "window_rules": [{
                "name": "managed",
                "matchers": [["match:class", "^(kitty)$"]],
                "effects": {"float": "on"},
            }],
            "layer_rules": [],
        }
        self.paths["windowrules"].write_text(
            legacy.MANAGED_STATE_PREFIX + json.dumps(state) + "\n"
            'hl.window_rule({ name = "manual", match = { title = "manual" }, pin = true })\n'
        )

        FakeRulesModule.SURFACE_PATHS = self.paths
        self.writes = []

        def writer(window, layer, autostart, env, *, surfaces):
            self.writes.append((window, layer, autostart, env, set(surfaces)))
            for surface in surfaces:
                self.paths[surface].write_text(f"written:{surface}\n")

        FakeRulesModule._write_conf = staticmethod(writer)
        self.reload = mock.Mock(return_value=SimpleNamespace(returncode=0, stdout="ok", stderr=""))
        self.session = rules_startup.RulesStartupSession(
            rules_module=FakeRulesModule,
            reload_runner=self.reload,
        )

    def test_open_returns_managed_and_locked_entries_with_matcher_modes(self):
        result = self.session.open()

        self.assertTrue(result["ok"])
        managed = result["data"]["window_rules"]
        self.assertEqual(managed[0]["name"], "managed")
        self.assertEqual(managed[0]["matchers"][0], {
            "property": "class", "mode": "exact", "value": "kitty",
        })
        locked = result["readonly"]["window_rules"]
        self.assertEqual([item["origin"] for item in locked], ["distro", "user-manual"])
        self.assertEqual([item["name"] for item in locked], ["distro", "manual"])
        self.assertIn("window_matchers", result["schema"])
        self.assertIn("window_effects", result["schema"])

    def test_save_writes_only_dirty_surface_and_reloads_rules(self):
        self.session.open()
        result = self.session.save({
            "dirty_surfaces": ["windowrules"],
            "window_rules": [{
                "name": "browser",
                "matchers": [{"property": "class", "mode": "contains", "value": "zen"}],
                "effects": {"float": "on"},
            }],
            "layer_rules": [],
            "autostart": [],
            "env_vars": [],
        })

        self.assertTrue(result["ok"])
        self.assertEqual(self.writes[0][4], {"windowrules"})
        self.assertEqual(self.writes[0][0][0].matchers, [("match:class", ".*zen.*")])
        self.reload.assert_called_once()

    def test_autostart_only_save_does_not_reload(self):
        self.session.open()
        result = self.session.save({
            "dirty_surfaces": ["autostart"],
            "window_rules": [], "layer_rules": [],
            "autostart": [{"command": "waybar", "exec_once": True}],
            "env_vars": [],
        })

        self.assertTrue(result["ok"])
        self.assertEqual(self.writes[0][4], {"autostart"})
        self.reload.assert_not_called()

    def test_external_change_blocks_save_without_overwriting(self):
        self.session.open()
        self.paths["windowrules"].write_text("changed outside Cloud Center\n")

        result = self.session.save({
            "dirty_surfaces": ["windowrules"],
            "window_rules": [], "layer_rules": [], "autostart": [], "env_vars": [],
        })

        self.assertFalse(result["ok"])
        self.assertEqual(result["reason"], "external_change")
        self.assertEqual(self.paths["windowrules"].read_text(), "changed outside Cloud Center\n")
        self.assertEqual(self.writes, [])

    def test_hand_editing_hyprland_lua_does_not_block_save(self):
        # hyprland.lua is no longer watched for external changes (its only
        # writer/reader dependency was removed elsewhere in this refactor) —
        # hand-editing it while this page is open must not falsely trip
        # external_change.
        main_lua = Path(self.tmp.name) / "hyprland.lua"
        main_lua.write_text("-- static hyprland.lua\n")
        self.session.open()
        main_lua.write_text("-- hand-edited while page was open\n")

        result = self.session.save({
            "dirty_surfaces": ["windowrules"],
            "window_rules": [], "layer_rules": [], "autostart": [], "env_vars": [],
        })

        self.assertTrue(result["ok"])

    def test_failure_restores_all_three_opening_files(self):
        self.session.open()
        original = {path: path.read_bytes() if path.exists() else None
                    for path in self.paths.values()}

        def broken_writer(window, layer, autostart, env, *, surfaces):
            self.paths["windowrules"].write_text("partial write\n")
            self.paths["autostart"].write_text("new file\n")
            raise RuntimeError("HCM failed")

        FakeRulesModule._write_conf = staticmethod(broken_writer)
        result = self.session.save({
            "dirty_surfaces": ["windowrules", "autostart"],
            "window_rules": [], "layer_rules": [], "autostart": [], "env_vars": [],
        })

        self.assertFalse(result["ok"])
        self.assertIn("HCM failed", result["message"])
        for path, content in original.items():
            current = path.read_bytes() if path.exists() else None
            self.assertEqual(current, content, str(path))

    def test_reload_failure_restores_files_and_reloads_restored_rules(self):
        self.session.open()
        before = self.paths["windowrules"].read_bytes()
        self.reload.side_effect = [
            SimpleNamespace(returncode=1, stdout="", stderr="invalid rule"),
            SimpleNamespace(returncode=0, stdout="ok", stderr=""),
        ]

        result = self.session.save({
            "dirty_surfaces": ["windowrules"],
            "window_rules": [], "layer_rules": [], "autostart": [], "env_vars": [],
        })

        self.assertFalse(result["ok"])
        self.assertIn("invalid rule", result["message"])
        self.assertEqual(self.paths["windowrules"].read_bytes(), before)
        self.assertEqual(self.reload.call_count, 2)

    def test_close_discards_session_without_touching_files(self):
        self.session.open()
        before = self.paths["windowrules"].read_bytes()
        result = self.session.close()
        self.assertTrue(result["ok"])
        self.assertEqual(self.paths["windowrules"].read_bytes(), before)
        self.assertFalse(self.session.is_open)


class MatcherModeTest(unittest.TestCase):
    def test_modes_round_trip_for_literal_text(self):
        from lib.ccd.rules_startup import decode_matcher, encode_matcher

        for mode in ("exact", "contains", "starts_with", "ends_with"):
            encoded = encode_matcher(mode, "Kitty (dev)")
            self.assertEqual(decode_matcher(encoded), (mode, "Kitty (dev)"))

    def test_unrecognised_pattern_is_regular_expression(self):
        from lib.ccd.rules_startup import decode_matcher

        self.assertEqual(decode_matcher("^(kitty|foot)$"), ("regex", "^(kitty|foot)$"))

    def test_legacy_exact_pattern_with_hyphens_is_recognised(self):
        from lib.ccd.rules_startup import decode_matcher

        self.assertEqual(
            decode_matcher("^(org-prismlauncher-EntryPoint)$"),
            ("exact", "org-prismlauncher-EntryPoint"),
        )

    def test_boolean_matcher_is_not_wrapped_as_a_regex(self):
        from lib.ccd import rules_startup

        item = rules_startup._window_from_json(FakeRulesModule, {
            "name": "xwayland",
            "matchers": [{"property": "xwayland", "mode": "exact", "value": "on"}],
            "effects": {},
        })
        self.assertEqual(item.matchers, [("match:xwayland", "on")])


class ProtocolRegistrationTest(unittest.TestCase):
    def test_rules_startup_methods_are_registered(self):
        from lib.ccd import rules_startup

        expected = {
            "open_rules_startup_session", "save_rules_startup",
            "close_rules_startup_session", "list_rule_windows",
            "list_rule_layers", "list_autostart_apps", "preview_rule",
        }
        self.assertTrue(expected.issubset(rules_startup.protocol.METHODS))


if __name__ == "__main__":
    unittest.main()
