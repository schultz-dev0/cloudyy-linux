from pathlib import Path
import re
import unittest

from lib.ccd import cursor


REPO_ROOT = Path(__file__).resolve().parents[3]
SOURCE_CURSOR = REPO_ROOT / ".config/hypr/source/cursor.lua"
SOURCE_VARIABLES = REPO_ROOT / ".config/hypr/source/variables.lua"
MAIN_LUA = REPO_ROOT / ".config/hypr/hyprland.lua"
DEPENDENCIES = REPO_ROOT / "install/dependencies.conf"


class CursorInstallContractTests(unittest.TestCase):
    def test_distro_cursor_module_contains_every_supported_option(self):
        source = SOURCE_CURSOR.read_text(encoding="utf-8")

        for setting in cursor.CURSOR_SCHEMA:
            self.assertRegex(
                source,
                rf"(?m)^\s*{re.escape(setting['key'])}\s*=",
                setting["key"],
            )

    def test_hyprland_switchboard_contains_source_and_user_cursor_pair(self):
        source = MAIN_LUA.read_text(encoding="utf-8")

        self.assertIn('require("source.cursor")', source)
        self.assertIn('require("user-configs.user_cursor")', source)

    def test_bibata_and_apple_cursor_families_are_mandatory_aur_dependencies(self):
        source = DEPENDENCIES.read_text(encoding="utf-8")
        start = source.index("MANDATORY_AUR_THEMING=(")
        end = source.index("\n)", start)
        theming_dependencies = source[start:end]

        self.assertIn('"bibata-cursor-git"', theming_dependencies)
        self.assertIn('"apple_hyprcursor"', theming_dependencies)
        self.assertIn('"apple_cursor"', theming_dependencies)
        self.assertNotIn('"sweet-cursors-hyprcursor-git"', theming_dependencies)

    def test_fresh_install_defaults_both_cursor_systems_to_bibata(self):
        source = SOURCE_VARIABLES.read_text(encoding="utf-8")

        self.assertIn('hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")', source)
        self.assertIn('hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")', source)
        self.assertIn('hl.env("HYPRCURSOR_SIZE", "24")', source)
        self.assertIn('hl.env("XCURSOR_SIZE", "24")', source)


if __name__ == "__main__":
    unittest.main()
