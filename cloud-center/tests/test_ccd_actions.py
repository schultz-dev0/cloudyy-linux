import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import lib.utility as utility
from lib.ccd import actions, model, protocol

FIXTURE_YAML = """
pages:
  - id: home
    title: Home
    layout:
      - type: section
        properties: {title: Test}
        items:
          - type: toggle
            properties: {title: Wifi, key: test/wifi}
            on_toggle:
              enabled:  {command: "echo enabled > {out}"}
              disabled: {command: "echo disabled > {out}"}
          - type: slider
            properties: {title: Gaps, key: test/gaps, min: 0, max: 40}
            on_change: {command: "echo {value}_{value_i}_{value_f} > {out}"}
          - type: selection
            properties:
              title: Blur
              key: test/blur
              options: [On, Off]
              options_map: {"On": true, "Off": false}
            on_change: {command: "echo {value}_{option} > {out}"}
          - type: button
            properties: {title: Jump, action: "navigate_page:appearance"}
          - type: button
            properties: {title: Broken}
            on_press: {command: "exit 3"}
          - type: multi_selection
            properties:
              title: Layouts
              key: test/layouts
              options: [dwindle, master]
            on_change: {command: "echo {value}_{option} > {out}"}
          - type: wallpaper_picker
            properties: {title: Wall, key: test/wall, directory: /tmp}
            on_select: {command: "echo {path} > {out}"}
"""


def wait_for(condition, timeout=5.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return True
        time.sleep(0.02)
    return False


class ActionsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        tmp_path = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

        self.out = tmp_path / "out.txt"
        config_path = tmp_path / "config.yaml"
        config_path.write_text(FIXTURE_YAML.replace("{out}", str(self.out)))

        settings_patch = mock.patch.object(
            utility, "SETTINGS_DIR", tmp_path / "settings"
        )
        settings_patch.start()
        self.addCleanup(settings_patch.stop)

        model.load_model(config_path)

        self.events = []
        events_patch = mock.patch.object(
            protocol, "write_line", lambda payload: self.events.append(payload)
        )
        events_patch.start()
        self.addCleanup(events_patch.stop)

    def action_done_events(self):
        return [e for e in self.events if e.get("event") == "action_done"]

    def run_and_wait(self, params):
        result = actions.run_action(params)
        self.assertTrue(wait_for(lambda: self.action_done_events()))
        return result


class TestExpandCommand(unittest.TestCase):
    def test_tilde_expands_to_home(self):
        expanded = utility.expand_command("~/scripts/x.sh")
        self.assertTrue(expanded.startswith(str(Path.home())))

    def test_bare_hcm_expands_to_binary_path(self):
        expanded = utility.expand_command("hcm apply general:gaps_in 8")
        self.assertTrue(expanded.startswith(utility.hcm_bin()))

    def test_hcm_inside_words_is_untouched(self):
        self.assertIn("searchcmd", utility.expand_command("echo searchcmd"))


class TestSubstitute(unittest.TestCase):
    def test_slider_values(self):
        cmd = actions.substitute("a {value} {value_i} {value_f}", value=12.0)
        self.assertEqual(cmd, "a 12 12 12.00")

    def test_slider_decimal_kept_compact(self):
        cmd = actions.substitute("{value}", value=0.550)
        self.assertEqual(cmd, "0.55")

    def test_mapped_bool_becomes_lowercase_string(self):
        cmd = actions.substitute("{value}|{option}", value="On", mapped=True)
        self.assertEqual(cmd, "true|On")


class TestRunAction(ActionsTest):
    def test_toggle_persists_and_runs_branch_command(self):
        self.run_and_wait({"item": "home/0/0", "value": True})
        self.assertTrue(wait_for(lambda: self.out.exists()))
        self.assertEqual(self.out.read_text().strip(), "enabled")
        self.assertIs(utility.load_setting("test/wifi", False), True)

    def test_toggle_disabled_branch(self):
        self.run_and_wait({"item": "home/0/0", "value": False})
        self.assertTrue(wait_for(lambda: self.out.exists()))
        self.assertEqual(self.out.read_text().strip(), "disabled")

    def test_slider_substitutes_and_persists(self):
        self.run_and_wait({"item": "home/0/1", "value": 12.5})
        self.assertTrue(wait_for(lambda: self.out.exists()))
        # int(round(12.5)) is 12 in Python (banker's rounding) — GTK app parity.
        self.assertEqual(self.out.read_text().strip(), "12.5_12_12.50")
        self.assertEqual(utility.load_setting("test/gaps", 0.0), 12.5)

    def test_selection_maps_value_and_keeps_option(self):
        self.run_and_wait({"item": "home/0/2", "value": "Off"})
        self.assertTrue(wait_for(lambda: self.out.exists()))
        self.assertEqual(self.out.read_text().strip(), "false_Off")
        self.assertEqual(utility.load_setting("test/blur", ""), "Off")

    def test_multi_selection_joins_values(self):
        self.run_and_wait({"item": "home/0/5", "values": ["dwindle", "master"]})
        self.assertTrue(wait_for(lambda: self.out.exists()))
        self.assertEqual(self.out.read_text().strip(), "dwindle,master_dwindle,master")
        self.assertEqual(utility.load_setting("test/layouts", ""), "dwindle,master")

    def test_wallpaper_picker_substitutes_path(self):
        self.run_and_wait({"item": "home/0/6", "path": "/tmp/x.jpg"})
        self.assertTrue(wait_for(lambda: self.out.exists()))
        self.assertEqual(self.out.read_text().strip(), "/tmp/x.jpg")
        self.assertEqual(utility.load_setting("test/wall", ""), "/tmp/x.jpg")

    def test_navigate_button_returns_target_without_running(self):
        result = actions.run_action({"item": "home/0/3"})
        self.assertEqual(result, {"navigate": "appearance"})

    def test_failing_command_emits_failed_action_done_and_toast(self):
        actions.run_action({"item": "home/0/4"})
        self.assertTrue(wait_for(lambda: self.action_done_events()))
        done = self.action_done_events()[0]
        self.assertEqual(done["item"], "home/0/4")
        self.assertFalse(done["ok"])
        self.assertTrue(any(e.get("event") == "toast" for e in self.events))

    def test_unknown_item_raises(self):
        with self.assertRaises(actions.UnknownItemError):
            actions.run_action({"item": "nope/9/9"})


class TestSettingsMethods(ActionsTest):
    def test_set_and_get_setting_roundtrip(self):
        actions.set_setting({"key": "test/thing", "value": "hello"})
        got = actions.get_setting({"key": "test/thing", "default": ""})
        self.assertEqual(got, "hello")

    def test_get_setting_default_type_drives_parsing(self):
        actions.set_setting({"key": "test/flag", "value": True})
        self.assertIs(actions.get_setting({"key": "test/flag", "default": False}), True)


if __name__ == "__main__":
    unittest.main()
