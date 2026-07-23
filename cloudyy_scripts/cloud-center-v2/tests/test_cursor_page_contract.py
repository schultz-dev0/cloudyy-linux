import json
from pathlib import Path
import subprocess
import unittest

from lib.ccd import model


REPO_ROOT = Path(__file__).resolve().parents[3]
POLICY = REPO_ROOT / ".config/quickshell/cloud-center/components/CursorPolicy.js"
PAGE = REPO_ROOT / ".config/quickshell/cloud-center/pages/CursorEditor.qml"
SHELL = REPO_ROOT / ".config/quickshell/cloud-center/shell.qml"
BACKEND = REPO_ROOT / ".config/quickshell/cloud-center/services/Backend.qml"


def evaluate(expression):
    if not POLICY.exists():
        raise AssertionError(f"missing QML policy module: {POLICY}")
    harness = r"""
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(process.argv[1], "utf8")
    .replace(/^\.pragma library\s*/, "");
const context = {};
vm.createContext(context);
vm.runInContext(source, context);
const result = vm.runInContext(process.argv[2], context);
process.stdout.write(JSON.stringify(result));
"""
    result = subprocess.run(
        ["node", "-e", harness, str(POLICY), expression],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise AssertionError(result.stderr.strip())
    return json.loads(result.stdout)


class CursorPolicyTests(unittest.TestCase):
    def test_zoom_details_enable_only_when_magnified(self):
        self.assertFalse(evaluate(
            'settingEnabled("zoom_rigid", { zoom_factor: 1.0 })'
        ))
        self.assertTrue(evaluate(
            'settingEnabled("zoom_rigid", { zoom_factor: 1.1 })'
        ))

    def test_vrr_refresh_rate_enables_when_protection_is_not_off(self):
        self.assertFalse(evaluate(
            'settingEnabled("min_refresh_rate", { no_break_fs_vrr: 0 })'
        ))
        self.assertTrue(evaluate(
            'settingEnabled("min_refresh_rate", { no_break_fs_vrr: 2 })'
        ))

    def test_theme_controls_follow_hyprcursor_enablement(self):
        self.assertFalse(evaluate(
            'appearanceEnabled({ enable_hyprcursor: false })'
        ))
        self.assertTrue(evaluate(
            'appearanceEnabled({ enable_hyprcursor: true })'
        ))


class CursorPageContractTests(unittest.TestCase):
    def test_model_routes_cursor_to_a_dedicated_qml_page(self):
        self.assertEqual(model.NATIVE_KIND_OVERRIDES.get("__cursor__"), "cursor")

        shell = SHELL.read_text(encoding="utf-8")
        self.assertIn('page.kind === "cursor" ? cursorComponent', shell)
        self.assertIn("CursorEditor { page: pageLoader.page }", shell)

    def test_page_owns_the_complete_session_lifecycle(self):
        source = PAGE.read_text(encoding="utf-8")

        self.assertIn('request("open_cursor_session"', source)
        self.assertIn('request("preview_cursor_option"', source)
        self.assertIn('request("preview_cursor_appearance"', source)
        self.assertIn('request("apply_cursor_settings"', source)
        self.assertIn('request("close_cursor_session"', source)
        self.assertIn("Component.onDestruction", source)

    def test_page_uses_policy_dependencies_and_invisible_confirmation(self):
        source = PAGE.read_text(encoding="utf-8")

        self.assertIn('import "../components/CursorPolicy.js" as CursorPolicy', source)
        self.assertIn("CursorPolicy.settingEnabled", source)
        self.assertIn('request("keep_cursor_invisible"', source)
        self.assertIn("cursorVisibilityEvent", BACKEND.read_text(encoding="utf-8"))

    def test_failed_apply_reconciles_the_page_with_backend_state(self):
        source = PAGE.read_text(encoding="utf-8")

        self.assertIn("function reconcileState(result)", source)
        self.assertIn("reconcileState(result);", source)

    def test_failed_discard_keeps_the_existing_session_open(self):
        source = PAGE.read_text(encoding="utf-8")

        self.assertIn("Could not discard cursor preview", source)

    def test_advanced_section_uses_cursor_specific_name(self):
        source = PAGE.read_text(encoding="utf-8")

        self.assertIn('text: "Advanced cursor"', source)
        self.assertNotIn('text: "Advanced display"', source)


if __name__ == "__main__":
    unittest.main()
