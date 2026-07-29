import json
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
POLICY = REPO_ROOT / ".config/quickshell/cloud-center/components/RuleEditorPolicy.js"
RULES_EDITOR = REPO_ROOT / ".config/quickshell/cloud-center/pages/RulesStartupEditor.qml"
ENTRY_ROW = REPO_ROOT / ".config/quickshell/cloud-center/components/RulesEntryRow.qml"


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


class RuleEditorPolicyTests(unittest.TestCase):
    def test_blank_rule_is_scaffolded_from_selected_window(self):
        result = evaluate("""
            applyPickedWindow("", [], {
                class: "org.quickshell",
                title: "Cloud Center",
                xwayland: false
            }, true)
        """)

        self.assertEqual(result, {
            "name": "quickshell",
            "matchers": [
                {"property": "class", "mode": "exact", "value": "org.quickshell"},
                {"property": "xwayland", "mode": "exact", "value": "off"},
            ],
        })

    def test_existing_rule_replaces_window_identity_without_duplicates(self):
        result = evaluate("""
            applyPickedWindow("old-minecraft-xwayland", [
                { property: "class", mode: "exact", value: "org-prismlauncher-EntryPoint" },
                { property: "xwayland", mode: "exact", value: "on" },
                { property: "title", mode: "contains", value: "Minecraft" },
                { property: "class", mode: "exact", value: "org.quickshell" }
            ], {
                class: "zen",
                title: "Browser",
                xwayland: false
            }, false)
        """)

        self.assertEqual(result, {
            "name": "old-minecraft-xwayland",
            "matchers": [
                {"property": "class", "mode": "exact", "value": "zen"},
                {"property": "xwayland", "mode": "exact", "value": "off"},
                {"property": "title", "mode": "contains", "value": "Minecraft"},
            ],
        })

    def test_text_edit_preserves_matcher_array_identity(self):
        result = evaluate("""
            (() => {
                const matchers = [
                    { property: "class", mode: "exact", value: "org.quickshell" },
                    { property: "title", mode: "contains", value: "Cloud" }
                ];
                const returned = setMatcherValueInPlace(matchers, 0, "org.example.App");
                return { sameArray: returned === matchers, matchers: matchers };
            })()
        """)

        self.assertEqual(result, {
            "sameArray": True,
            "matchers": [
                {"property": "class", "mode": "exact", "value": "org.example.App"},
                {"property": "title", "mode": "contains", "value": "Cloud"},
            ],
        })

    def test_window_picker_uses_context_aware_policy(self):
        source = RULES_EDITOR.read_text(encoding="utf-8")

        self.assertIn(
            'import "../components/RuleEditorPolicy.js" as RuleEditorPolicy', source
        )
        self.assertIn("function applyPickedWindow(window)", source)
        self.assertIn("RuleEditorPolicy.applyPickedWindow(", source)
        self.assertNotIn(
            'rulesPage.addMatcher("class", modelData.class || "")', source
        )

    def test_matcher_text_field_uses_in_place_value_update(self):
        source = RULES_EDITOR.read_text(encoding="utf-8")

        self.assertIn("function setMatcherValue(index, value)", source)
        self.assertIn("RuleEditorPolicy.setMatcherValueInPlace(", source)
        self.assertIn(
            "onTextEdited: value => rulesPage.setMatcherValue(matcherRow.index, value)",
            source,
        )

    def test_add_entry_uses_a_dedicated_new_editor_action(self):
        editor = RULES_EDITOR.read_text(encoding="utf-8")
        entry_row = ENTRY_ROW.read_text(encoding="utf-8")

        self.assertIn("function openNewEditor()", editor)
        self.assertIn("onClicked: rulesPage.openNewEditor()", editor)
        self.assertNotIn(
            "TapHandler { enabled: row.editable; onTapped: row.editRequested() }",
            entry_row,
        )


if __name__ == "__main__":
    unittest.main()
