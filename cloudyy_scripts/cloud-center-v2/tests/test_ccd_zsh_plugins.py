import importlib
import unittest
from unittest import mock


class CcdZshPluginsTests(unittest.TestCase):
    def setUp(self):
        self.mod = importlib.import_module("lib.ccd.zsh_plugins")
        self.mod = importlib.reload(self.mod)

    def test_methods_registered(self):
        from lib.ccd import protocol
        self.assertIn("list_zsh_plugins", protocol.METHODS)
        self.assertIn("set_zsh_plugin", protocol.METHODS)

    def test_sidecar_imports_zsh_plugins(self):
        entrypoint_path = importlib.import_module("lib.ccd.__main__").__file__
        with open(entrypoint_path, encoding="utf-8") as handle:
            entrypoint = handle.read()
        self.assertIn("zsh_plugins,", entrypoint)

    def test_list_delegates(self):
        with mock.patch.object(
            self.mod.zsh_plugins_core, "list_plugins",
            return_value={"plugins": [], "total": 0, "active_count": 0, "truncated": False, "error": ""},
        ) as listed:
            result = self.mod.list_zsh_plugins({"query": "git", "enabled_only": True, "limit": 10})
            listed.assert_called_once_with(query="git", enabled_only=True, limit=10)
            self.assertEqual(result["plugins"], [])

    def test_set_validates(self):
        with self.assertRaisesRegex(ValueError, "boolean"):
            self.mod.set_zsh_plugin({"name": "docker", "enabled": "yes"})
        with self.assertRaisesRegex(ValueError, "non-empty"):
            self.mod.set_zsh_plugin({"name": "", "enabled": True})


if __name__ == "__main__":
    unittest.main()
