import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
QML_ROOT = REPO_ROOT / ".config" / "quickshell" / "cloud-center"
COMPONENTS = QML_ROOT / "components"
RULES_EDITOR = QML_ROOT / "pages" / "RulesStartupEditor.qml"


class CloudDialogDesignTest(unittest.TestCase):
    def test_reusable_cloud_dialog_controls_exist(self):
        expected = {
            "CloudButton.qml",
            "CloudDialog.qml",
            "CloudSelect.qml",
            "CloudSwitch.qml",
            "CloudTextField.qml",
            "RuleEffectRow.qml",
        }
        existing = {path.name for path in COMPONENTS.glob("*.qml")}
        self.assertTrue(expected <= existing, expected - existing)

    def test_rules_workflow_uses_cloud_dialog_for_every_popup(self):
        text = RULES_EDITOR.read_text(encoding="utf-8")
        self.assertGreaterEqual(text.count("CloudDialog {"), 3)
        self.assertNotRegex(text, r"(?m)^\s*Popup\s*\{")

    def test_rules_dialog_does_not_use_platform_styled_controls(self):
        text = RULES_EDITOR.read_text(encoding="utf-8")
        stock = re.findall(r"(?m)^\s*(Button|TextField|ComboBox|CheckBox)\s*\{", text)
        self.assertEqual(stock, [], f"platform controls remain: {stock}")

    def test_effects_use_explanatory_cloud_setting_rows(self):
        text = RULES_EDITOR.read_text(encoding="utf-8")
        self.assertIn("RuleEffectRow {", text)
        effect_row = (COMPONENTS / "RuleEffectRow.qml").read_text(encoding="utf-8")
        self.assertIn("property string description", effect_row)
        self.assertIn("CloudSwitch", effect_row)


if __name__ == "__main__":
    unittest.main()
