import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from lib import rules_startup_page as rules


SOURCE_WINDOWRULES = '''-- Window rules
hl.window_rule({
    name = "distro-rule",
    match = { class = "^(distro)$" },
    float = true,
})
'''

SOURCE_AUTOSTART = '''-- Autostart
hl.on("hyprland.start", function()
    hl.exec_cmd("distro-daemon")
end)
'''

SOURCE_VARIABLES = '''-- Variables
hl.env("TERMINAL", "kitty")
'''


class RulesStartupSplitTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.hypr = Path(self.tmp.name)
        self.source = self.hypr / "source"
        self.users = self.hypr / "user-configs"
        self.source.mkdir()
        self.users.mkdir()

        self.source_windowrules = self.source / "windowrules.lua"
        self.source_autostart = self.source / "autostart.lua"
        self.source_variables = self.source / "variables.lua"
        self.source_windowrules.write_text(SOURCE_WINDOWRULES)
        self.source_autostart.write_text(SOURCE_AUTOSTART)
        self.source_variables.write_text(SOURCE_VARIABLES)

        self.user_windowrules = self.users / "user_windowrules.lua"
        self.user_autostart = self.users / "user_autostart.lua"
        self.user_variables = self.users / "user_variables.lua"
        self.legacy = self.users / "user_rules_startup.lua"
        self.main = self.hypr / "hyprland.lua"
        self.main.write_text(
            'require("source.variables")\n'
            'require("source.autostart")\n'
            'require("source.windowrules")\n'
            'require("source.bindings")\n'
            'require("user-configs.user_rules_startup") -- managed by Cloud Center\n'
        )

        values = {
            "HYPR_DIR": self.hypr,
            "MAIN_LUA": self.main,
            "USER_DIR": self.users,
            "LEGACY_CONF_PATH": self.legacy,
            "CONF_PATH": self.legacy,
            "WINDOWRULES_CONF_PATH": self.user_windowrules,
            "AUTOSTART_CONF_PATH": self.user_autostart,
            "VARIABLES_CONF_PATH": self.user_variables,
            "SOURCE_WINDOWRULES": self.source_windowrules,
            "SOURCE_AUTOSTART": self.source_autostart,
            "SOURCE_VARIABLES": self.source_variables,
            "SURFACE_PATHS": {
                "windowrules": (self.source_windowrules, self.user_windowrules),
                "autostart": (self.source_autostart, self.user_autostart),
                "variables": (self.source_variables, self.user_variables),
            },
        }
        patcher = mock.patch.multiple(rules, **values)
        patcher.start()
        self.addCleanup(patcher.stop)

        self.activated: list[str] = []
        activate = mock.patch.object(
            rules,
            "_activate_surface",
            side_effect=lambda surface: self.activated.append(surface),
        )
        activate.start()
        self.addCleanup(activate.stop)

    def test_first_edit_creates_only_the_touched_surface(self):
        user_rule = rules.WindowRule(
            name="user-rule",
            matchers=[("match:class", "^(user)$")],
            effects={"float": "on"},
        )

        rules._write_conf([user_rule], [], [], [], surfaces={"windowrules"})

        self.assertTrue(self.user_windowrules.exists())
        self.assertFalse(self.user_autostart.exists())
        self.assertFalse(self.user_variables.exists())
        text = self.user_windowrules.read_text()
        self.assertIn(SOURCE_WINDOWRULES.strip(), text)
        self.assertIn('name = "user-rule"', text)
        self.assertIn(rules.MANAGED_STATE_PREFIX, text)
        self.assertNotIn(rules.LEGACY_MANAGED_STATE_PREFIX, text)
        self.assertEqual(self.activated, ["windowrules"])

    def test_rewrite_preserves_manual_lua_outside_managed_block(self):
        self.user_windowrules.write_text(
            SOURCE_WINDOWRULES
            + '\nhl.layer_rule({ name = "manual", match = { namespace = "manual" } })\n'
        )
        first = rules.WindowRule("one", [("match:class", "one")], {"float": "on"})
        second = rules.WindowRule("two", [("match:class", "two")], {"center": "on"})

        rules._write_conf([first], [], [], [], surfaces={"windowrules"})
        rules._write_conf([second], [], [], [], surfaces={"windowrules"})

        text = self.user_windowrules.read_text()
        self.assertIn('name = "manual"', text)
        self.assertNotIn('name = "one"', text)
        self.assertIn('name = "two"', text)
        self.assertEqual(text.count(rules.MANAGED_BEGIN), 1)
        self.assertEqual(text.count(rules.MANAGED_END), 1)

    def test_legacy_migration_splits_flat_state_and_manual_lua(self):
        state = {
            "window_rules": [{
                "name": "old-minecraft-xwayland",
                "match": {"class": "^(prismlauncher)$", "xwayland": True},
                "float": True,
                "size": "1600 900",
            }],
            "layer_rules": [],
            "autostart": [],
            "env_vars": [{"name": "XCURSOR_THEME", "value": "Afterglow"}],
        }
        self.legacy.write_text(
            "-- Cloud Center user override file for rules and startup hooks.\n"
            + rules.LEGACY_MANAGED_STATE_PREFIX + json.dumps(state) + "\n\n"
            + '''hl.env("XCURSOR_THEME", "Afterglow")

hl.window_rule({
    name = "old-minecraft-xwayland",
    match = { class = "^(prismlauncher)$", xwayland = true },
    float = true,
    size = "1600 900",
})

hl.layer_rule({
    name = "manual-calculator",
    match = { namespace = "calculator" },
    blur = true,
})

hl.on("hyprland.start", function()
    local scripts = os.getenv("HOME") .. "/cloudyy_scripts"
    hl.exec_cmd(scripts .. "/ssh-auth.sh")
end)
'''
        )

        self.assertTrue(rules.migrate_legacy_conf())

        self.assertFalse(self.legacy.exists())
        self.assertFalse((self.hypr / ".legacy").exists())
        self.assertEqual(
            self.activated,
            ["windowrules", "autostart", "variables"],
        )

        window_text = self.user_windowrules.read_text()
        self.assertIn(SOURCE_WINDOWRULES.strip(), window_text)
        self.assertEqual(window_text.count('name = "old-minecraft-xwayland"'), 1)
        self.assertIn('name = "manual-calculator"', window_text)
        self.assertIn('xwayland = true', window_text)

        autostart_text = self.user_autostart.read_text()
        self.assertIn(SOURCE_AUTOSTART.strip(), autostart_text)
        self.assertIn('scripts .. "/ssh-auth.sh"', autostart_text)
        self.assertNotIn('"scripts .. \\"/ssh-auth.sh\\""', autostart_text)

        variable_text = self.user_variables.read_text()
        self.assertIn(SOURCE_VARIABLES.strip(), variable_text)
        self.assertEqual(variable_text.count('hl.env("XCURSOR_THEME", "Afterglow")'), 1)

        main_text = self.main.read_text()
        self.assertNotIn("user_rules_startup", main_text)
        self.assertLess(
            main_text.index('require("user-configs.user_variables")'),
            main_text.index('require("source.bindings")'),
        )
        for surface in ("windowrules", "autostart", "variables"):
            self.assertIn(f'-- require("source.{surface}")', main_text)
            self.assertIn(
                f'require("user-configs.user_{surface}") -- managed by Cloud Center',
                main_text,
            )

    def test_migration_is_a_noop_without_legacy_file(self):
        self.assertFalse(rules.migrate_legacy_conf())
        self.assertEqual(self.activated, [])


if __name__ == "__main__":
    unittest.main()
