import tempfile
import unittest
from pathlib import Path

from lib import zsh_plugins_core


class ZshPluginsCoreTests(unittest.TestCase):
    def test_scan_and_filter(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            plugins = root / "plugins"
            custom = root / "custom"
            active = root / "active.txt"
            (plugins / "docker").mkdir(parents=True)
            (plugins / "docker" / "README.md").write_text(
                "# Docker\n\nDocker helpers for oh-my-zsh.\n", encoding="utf-8",
            )
            (custom / "zsh-autosuggestions").mkdir(parents=True)
            active.write_text("zsh-autosuggestions\n", encoding="utf-8")

            result = zsh_plugins_core.list_plugins(
                plugins_dir=plugins,
                custom_dir=custom,
                active_path=active,
                limit=0,
            )
            names = [p["name"] for p in result["plugins"]]
            self.assertEqual(names, ["zsh-autosuggestions", "docker"])
            self.assertTrue(result["plugins"][0]["enabled"])
            self.assertFalse(result["plugins"][1]["enabled"])
            self.assertIn("Docker helpers", result["plugins"][1]["desc"])

            filtered = zsh_plugins_core.list_plugins(
                query="auto",
                plugins_dir=plugins,
                custom_dir=custom,
                active_path=active,
            )
            self.assertEqual([p["name"] for p in filtered["plugins"]], ["zsh-autosuggestions"])

            enabled = zsh_plugins_core.list_plugins(
                enabled_only=True,
                plugins_dir=plugins,
                custom_dir=custom,
                active_path=active,
            )
            self.assertEqual(len(enabled["plugins"]), 1)

    def test_set_plugin_writes_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            active = Path(tmp) / "active.txt"
            result = zsh_plugins_core.set_plugin_enabled(
                "docker", True, active_path=active,
            )
            self.assertTrue(result["ok"])
            self.assertEqual(active.read_text(encoding="utf-8"), "docker\n")
            zsh_plugins_core.set_plugin_enabled("docker", False, active_path=active)
            self.assertEqual(active.read_text(encoding="utf-8"), "")

    def test_set_plugin_requires_name(self):
        with self.assertRaisesRegex(ValueError, "plugin name"):
            zsh_plugins_core.set_plugin_enabled("  ", True)


if __name__ == "__main__":
    unittest.main()
