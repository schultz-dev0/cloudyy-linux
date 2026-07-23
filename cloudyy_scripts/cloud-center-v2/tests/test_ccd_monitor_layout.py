import importlib
import unittest


def load_layout_module():
    try:
        return importlib.import_module("lib.ccd.monitor_layout")
    except ModuleNotFoundError:
        return None


class TestLogicalGeometry(unittest.TestCase):
    def test_uses_draft_mode_scale_and_rotated_dimensions(self):
        layout = load_layout_module()
        self.assertIsNotNone(layout, "lib.ccd.monitor_layout must exist")
        draft = {
            "mode": "2560x1440@120.00Hz",
            "width": 1920,
            "height": 1080,
            "scale": 2.0,
            "transform": 3,
        }
        self.assertEqual(layout.logical_size(draft), (720, 1280))

    def test_custom_modeline_falls_back_to_runtime_dimensions(self):
        layout = load_layout_module()
        self.assertIsNotNone(layout, "lib.ccd.monitor_layout must exist")
        draft = {
            "mode": "modeline 1071.101 3840 3848 3880",
            "width": 3440,
            "height": 1440,
            "scale": 1.0,
            "transform": 0,
        }
        self.assertEqual(layout.logical_size(draft), (3440, 1440))


class TestLuaMonitorRules(unittest.TestCase):
    def test_builds_supported_advanced_fields(self):
        layout = load_layout_module()
        self.assertIsNotNone(layout, "lib.ccd.monitor_layout must exist")
        line = layout.build_monitor_line({
            "name": "DP-1",
            "mode": "3440x1440@180.00Hz",
            "x": 1120,
            "y": -631,
            "scale": 1.0,
            "transform": 0,
            "enabled": True,
            "mirror_of": "",
            "bitdepth": 10,
            "cm": "hdr",
            "sdr_eotf": "gamma22",
            "sdrbrightness": 1.2,
            "sdrsaturation": 0.98,
            "vrr": 3,
            "icc": "",
        })
        self.assertIn('mode = "3440x1440@180.00"', line)
        self.assertIn("bitdepth = 10", line)
        self.assertIn('cm = "hdr"', line)
        self.assertIn('sdr_eotf = "gamma22"', line)
        self.assertIn("sdrbrightness = 1.2", line)
        self.assertIn("sdrsaturation = 0.98", line)
        self.assertIn("vrr = 3", line)

    def test_disabled_rule_uses_current_lua_field_name(self):
        layout = load_layout_module()
        self.assertIsNotNone(layout, "lib.ccd.monitor_layout must exist")
        line = layout.build_monitor_line({"name": "DP-2", "enabled": False})
        self.assertEqual(line, 'hl.monitor({ output = "DP-2", disabled = true })')

    def test_parses_advanced_fields_from_existing_rule(self):
        layout = load_layout_module()
        self.assertIsNotNone(layout, "lib.ccd.monitor_layout must exist")
        fields = layout.parse_monitor_line(
            'hl.monitor({ output = "DP-1", mode = "2560x1440@120", '
            'position = "0x0", scale = 1, bitdepth = 10, cm = "wide", '
            'vrr = 2, icc = "/profiles/display.icc" })'
        )
        self.assertEqual(fields["output"], "DP-1")
        self.assertEqual(fields["bitdepth"], 10)
        self.assertEqual(fields["cm"], "wide")
        self.assertEqual(fields["vrr"], 2)
        self.assertEqual(fields["icc"], "/profiles/display.icc")


class TestWholeConfigRendering(unittest.TestCase):
    def test_replaces_layout_rules_and_preserves_unrelated_bytes(self):
        layout = load_layout_module()
        self.assertIsNotNone(layout, "lib.ccd.monitor_layout must exist")
        original = (
            "-- custom preface\n"
            'hl.monitor({ output = "OLD", mode = "1920x1080@60", position = "0x0", scale = 1 })\n'
            'hl.workspace_rule({ workspace = "1", monitor = "OLD" })\n'
            'hl.workspace_rule({ workspace = "special:music", persistent = true })\n'
            "-- custom suffix\n"
        )
        drafts = [{
            "name": "DP-1", "mode": "2560x1440@120Hz", "x": 0, "y": 0,
            "scale": 1.0, "transform": 0, "enabled": True, "mirror_of": "",
            "workspaces": ["1", "dev"],
        }]
        rendered = layout.render_layout_config(original, drafts)
        self.assertIn("-- custom preface\n", rendered)
        self.assertIn('hl.workspace_rule({ workspace = "special:music", persistent = true })\n', rendered)
        self.assertIn("-- custom suffix\n", rendered)
        self.assertNotIn('output = "OLD"', rendered)
        self.assertIn('output = "DP-1"', rendered)
        self.assertIn('workspace = "1", monitor = "DP-1"', rendered)
        self.assertIn('workspace = "dev", monitor = "DP-1"', rendered)


if __name__ == "__main__":
    unittest.main()
