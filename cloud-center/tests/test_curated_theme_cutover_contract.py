"""Cutover contracts for removing independent mode controls and automation."""

from __future__ import annotations

import json
from pathlib import Path
import re
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]


class CuratedThemeCutoverContractTests(unittest.TestCase):
    def test_cloud_center_has_wallpaper_controls_but_no_palette_generator_controls(self):
        source = (ROOT / "cloud-center/config.yaml").read_text()
        config = yaml.safe_load(source)
        items = [
            item
            for page in config["pages"]
            for section in page.get("layout", [])
            for item in section.get("items", [])
        ]
        titles = {item.get("properties", {}).get("title") for item in items}
        self.assertIn("Wallpaper", titles)
        self.assertIn("Wallpaper Browser", titles)
        self.assertFalse({"Dark Mode", "Color Scheme", "Contrast", "Apply Theme"} & titles)
        self.assertNotRegex(source, r"cloudyy-theme\s+(?:toggle|set\s+--mode|refresh)\b")
        self.assertNotIn("--mode {mode}", source)
        self.assertNotIn("Matugen", source)

    def test_shell_and_command_registries_retain_wallpaper_cycle_without_automode(self):
        notif = (ROOT / ".config/quickshell/NotifPanel.qml").read_text()
        commands = json.loads(
            (ROOT / ".config/quickshell/modules/commandcenter/commands.json").read_text()
        )
        ids = {entry["id"] for entry in commands}
        operations = {
            entry.get("action", {}).get("op") for entry in commands
            if entry.get("action", {}).get("type") == "cycle"
        }
        cycle_script = (
            ROOT / ".config/quickshell/modules/commandcenter/scripts/cycle-ctl.sh"
        ).read_text()

        self.assertIn("DndTile {", notif)
        self.assertIn("NightLightTile {", notif)
        self.assertNotIn("DarkModeTile", notif)
        self.assertFalse((
            ROOT / ".config/quickshell/modules/controlcenter/tiles/DarkModeTile.qml"
        ).exists())
        self.assertIn("cycle.toggle", ids)
        self.assertIn("toggle-cycle", operations)
        self.assertFalse(any(identifier.startswith("cycle.automode") for identifier in ids))
        self.assertFalse({"toggle-automode", "set-light-hour", "set-dark-hour"} & operations)
        self.assertNotIn("AUTOMODE", cycle_script)
        self.assertNotIn("theme-automode", cycle_script)

    def test_all_obsolete_command_producers_are_removed(self):
        paths = (
            ROOT / "cloud-center/config.yaml",
            ROOT / ".config/quickshell/NotifPanel.qml",
            ROOT / ".config/quickshell/modules/spotlight/SpotlightService.qml",
            ROOT / ".config/quickshell/modules/commandcenter/commands.json",
            ROOT / ".config/quickshell/modules/commandcenter/scripts/cycle-ctl.sh",
            ROOT / ".config/swaync/config.json",
            ROOT / "install/assets/defaults/hypr/bindings.lua",
        )
        forbidden = re.compile(
            r"cloudyy-theme\s+(?:toggle|set\s+--mode|refresh)\b|"
            r"toggle-automode|set-light-hour|set-dark-hour|theme-automode"
        )
        offenders = {
            str(path.relative_to(ROOT)): forbidden.findall(path.read_text())
            for path in paths if forbidden.search(path.read_text())
        }
        self.assertEqual(offenders, {})
        self.assertFalse((ROOT / "bin/cloudyy-quickshell-automode-switch").exists())

    def test_online_wallpaper_application_is_image_only(self):
        source = (ROOT / "cloud-center/lib/ccd/online_wallpapers.py").read_text()
        qml = (ROOT / ".config/quickshell/cloud-center/components/OnlineWallpaperBrowser.qml").read_text()
        self.assertNotIn('.replace("{mode}"', source)
        self.assertIn('"{mode}" in apply_command', source)
        self.assertNotIn("applying a wallpaper", source.lower())
        self.assertIn("mode: browser.targetMode", qml)
        self.assertIn("dark_directory", qml)
        self.assertIn("light_directory", qml)

    def test_declared_mode_comes_only_from_read_only_curated_cli(self):
        source = (ROOT / "cloud-center/lib/ccd/model.py").read_text()
        self.assertIn('"get-mode"', source)
        self.assertIn("subprocess.run", source)
        self.assertNotIn("THEME_STATE", source)
        self.assertNotIn('load_setting("theme/dark_mode"', source)

    def test_owned_automode_retirement_is_a_recorded_adapter(self):
        common = (ROOT / "lib/cloudyy-theme/common.sh").read_text()
        adapters = (ROOT / "lib/cloudyy-theme/adapters.sh").read_text()
        self.assertIn("retire-automode", common)
        self.assertIn("adapter_retire_automode", adapters)
        self.assertIn("retire-automode:adapter_retire_automode", common)
        self.assertIn("cloudyy-quickshell-automode-switch", adapters)
        self.assertIn("theme-automode.timer", adapters)

    def test_existing_hypr_modules_have_an_owned_recorded_migration(self):
        common = (ROOT / "lib/cloudyy-theme/common.sh").read_text()
        adapters = (ROOT / "lib/cloudyy-theme/adapters.sh").read_text()
        self.assertIn("migrate-hypr-modules", common)
        self.assertIn("adapter_hypr_modules", adapters)
        self.assertIn("migrate-hypr-modules:adapter_hypr_modules", common)


if __name__ == "__main__":
    unittest.main()
