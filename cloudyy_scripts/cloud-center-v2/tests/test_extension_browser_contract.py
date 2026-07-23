from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[3]
PAGE = REPO_ROOT / ".config/quickshell/cloud-center/pages/YamlPage.qml"
BROWSER = REPO_ROOT / ".config/quickshell/cloud-center/components/ExtensionBrowser.qml"
STATE = REPO_ROOT / ".config/quickshell/cloud-center/components/ExtensionBrowserState.js"
MAIN = REPO_ROOT / "cloudyy_scripts/cloud-center-v2/lib/ccd/__main__.py"


class ExtensionBrowserContractTests(unittest.TestCase):
    def test_files_exist(self):
        for path in (PAGE, BROWSER, STATE):
            self.assertTrue(path.is_file(), path)

    def test_yaml_page_uses_native_browser(self):
        source = PAGE.read_text(encoding="utf-8")
        self.assertIn("extension_browser", source)
        self.assertIn("ExtensionBrowser", source)
        self.assertNotIn("Open in legacy app", source)

    def test_browser_uses_protocol(self):
        source = BROWSER.read_text(encoding="utf-8")
        self.assertIn("list_zsh_plugins", source)
        self.assertIn("set_zsh_plugin", source)
        self.assertIn("Enabled Only", source)
        self.assertIn("Search Zsh plugins", source)

    def test_sidecar_registers_module(self):
        source = MAIN.read_text(encoding="utf-8")
        self.assertIn("zsh_plugins", source)


if __name__ == "__main__":
    unittest.main()
