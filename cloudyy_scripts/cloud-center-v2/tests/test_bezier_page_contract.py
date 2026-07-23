from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[3]
DIALOG = REPO_ROOT / ".config/quickshell/cloud-center/components/BezierEditorDialog.qml"
MATH = REPO_ROOT / ".config/quickshell/cloud-center/components/BezierMath.js"
BUTTON = REPO_ROOT / ".config/quickshell/cloud-center/components/RowButton.qml"
SHELL = REPO_ROOT / ".config/quickshell/cloud-center/shell.qml"
BACKEND = REPO_ROOT / ".config/quickshell/cloud-center/services/Backend.qml"
ACTIONS = REPO_ROOT / "cloudyy_scripts/cloud-center-v2/lib/ccd/actions.py"


class BezierEditorContractTests(unittest.TestCase):
    def test_files_exist(self):
        for path in (DIALOG, MATH, BUTTON, SHELL, BACKEND):
            self.assertTrue(path.is_file(), path)

    def test_dialog_uses_protocol_and_feel_first_copy(self):
        source = DIALOG.read_text(encoding="utf-8")
        for method in (
            "list_bezier_curves",
            "apply_bezier_curve",
            "delete_bezier_curve",
        ):
            self.assertIn(method, source)
        self.assertIn("Window animation feel", source)
        self.assertIn("Save & use on windows", source)
        self.assertIn("Fine-tune", source)

    def test_button_opens_native_dialog(self):
        source = BUTTON.read_text(encoding="utf-8")
        self.assertIn("bezier_editor", source)
        self.assertIn("requestBezierEditor", source)
        self.assertNotIn("cloud-center.py", source)

    def test_shell_and_backend_wire_dialog(self):
        shell = SHELL.read_text(encoding="utf-8")
        backend = BACKEND.read_text(encoding="utf-8")
        self.assertIn("BezierEditorDialog", shell)
        self.assertIn("onBezierEditorRequested", shell)
        self.assertIn("bezierEditorRequested", backend)

    def test_action_returns_open(self):
        source = ACTIONS.read_text(encoding="utf-8")
        self.assertIn('"open": action_id', source)


if __name__ == "__main__":
    unittest.main()
