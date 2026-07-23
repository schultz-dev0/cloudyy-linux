from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[3]
LAUNCH_PATHS = [
    REPO_ROOT / ".config/hypr/source/bindings.lua",
    REPO_ROOT / ".config/swaync/config.json",
    REPO_ROOT / "install/seed-required-applications.sh",
    REPO_ROOT / "cloudyy_scripts/cloud-center-v2/cc-restart.sh",
    REPO_ROOT / ".config/quickshell/cloud-center/shell.qml",
    REPO_ROOT / ".config/quickshell/cloud-center/components/RowButton.qml",
]
DEBUG_SCRIPT = REPO_ROOT / "cloudyy_scripts/cloud-center-v2/cc-debug.sh"


class GtkLaunchCutoverTests(unittest.TestCase):
    def test_launchers_do_not_invoke_gtk_app(self):
        for path in LAUNCH_PATHS:
            self.assertTrue(path.is_file(), path)
            source = path.read_text(encoding="utf-8")
            self.assertNotIn("cloud-center.py", source, path)
            self.assertNotIn("DeepLink", source, path)
            self.assertNotIn("uwsmp-app", source, path)
            self.assertNotRegex(
                source, r"python3\s+[^\n]*cloud-center\.py", path.name,
            )

    def test_debug_script_launches_qml_wrapper(self):
        source = DEBUG_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('LAUNCHER="$HOME/cloudyy_scripts/cloud-center"', source)
        self.assertNotRegex(source, r'nohup\s+python3\s+"\$SCRIPT"')
        self.assertIn('nohup "$LAUNCHER"', source)

    def test_shell_has_no_native_deeplink_branch(self):
        shell = (REPO_ROOT / ".config/quickshell/cloud-center/shell.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn('kind === "native"', shell)
        self.assertNotIn("deepLinkComponent", shell)

    def test_deeplink_page_removed(self):
        path = REPO_ROOT / ".config/quickshell/cloud-center/pages/DeepLink.qml"
        self.assertFalse(path.exists(), path)

    def test_model_pages_have_no_deep_link(self):
        from lib.ccd import model
        result = model.load_model()
        for page in result["pages"]:
            self.assertNotIn("deep_link", page, page.get("id"))


if __name__ == "__main__":
    unittest.main()
