import importlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


EXPECTED_CURSOR_KEYS = {
    "invisible",
    "sync_gsettings_theme",
    "no_hardware_cursors",
    "no_break_fs_vrr",
    "min_refresh_rate",
    "hotspot_padding",
    "inactive_timeout",
    "no_warps",
    "persistent_warps",
    "warp_on_change_workspace",
    "warp_on_toggle_special",
    "default_monitor",
    "zoom_factor",
    "zoom_rigid",
    "zoom_disable_aa",
    "zoom_detached_camera",
    "enable_hyprcursor",
    "hide_on_key_press",
    "hide_on_touch",
    "hide_on_tablet",
    "use_cpu_buffer",
    "warp_back_after_non_mouse_input",
}


def load_cursor_module():
    spec = importlib.util.find_spec("lib.ccd.cursor")
    if spec is None:
        raise AssertionError("lib.ccd.cursor must provide the Cursor backend")
    return importlib.import_module("lib.ccd.cursor")


class CursorSchemaTests(unittest.TestCase):
    def test_schema_covers_every_hyprland_055_cursor_option(self):
        cursor = load_cursor_module()

        self.assertEqual(
            {item["key"] for item in cursor.CURSOR_SCHEMA},
            EXPECTED_CURSOR_KEYS,
        )

    def test_tri_state_settings_use_exact_zero_one_two_values(self):
        cursor = load_cursor_module()
        schema = {item["key"]: item for item in cursor.CURSOR_SCHEMA}

        for key in (
            "no_hardware_cursors",
            "no_break_fs_vrr",
            "use_cpu_buffer",
            "warp_on_change_workspace",
            "warp_on_toggle_special",
        ):
            self.assertEqual(schema[key]["values"], [0, 1, 2], key)

    def test_defaults_match_hyprland_055(self):
        cursor = load_cursor_module()
        defaults = {item["key"]: item["default"] for item in cursor.CURSOR_SCHEMA}

        self.assertEqual(defaults["no_hardware_cursors"], 2)
        self.assertEqual(defaults["no_break_fs_vrr"], 2)
        self.assertEqual(defaults["use_cpu_buffer"], 2)
        self.assertEqual(defaults["min_refresh_rate"], 24)
        self.assertEqual(defaults["zoom_factor"], 1.0)
        self.assertTrue(defaults["zoom_detached_camera"])
        self.assertTrue(defaults["enable_hyprcursor"])
        self.assertTrue(defaults["hide_on_touch"])


class CursorThemeTests(unittest.TestCase):
    def test_discovers_only_directories_with_hyprcursor_manifests(self):
        cursor = load_cursor_module()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Sweet-cursors" / "hyprcursors").mkdir(parents=True)
            (root / "Sweet-cursors" / "manifest.hl").write_text(
                "name = Sweet-cursors\ndescription = Soft cursor theme\n",
                encoding="utf-8",
            )
            (root / "Legacy-only" / "cursors").mkdir(parents=True)
            (root / "Not-a-theme").mkdir()

            themes = cursor.discover_hyprcursor_themes([root])

        self.assertEqual(themes, [{
            "id": "Sweet-cursors",
            "name": "Sweet-cursors",
            "description": "Soft cursor theme",
        }])

    def test_theme_discovery_deduplicates_by_manifest_name(self):
        cursor = load_cursor_module()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = root / "one" / "Sweet"
            second = root / "two" / "Sweet-copy"
            first.mkdir(parents=True)
            second.mkdir(parents=True)
            first.joinpath("manifest.hl").write_text("name = Sweet\n", encoding="utf-8")
            second.joinpath("manifest.hl").write_text("name = Sweet\n", encoding="utf-8")

            themes = cursor.discover_hyprcursor_themes([root / "one", root / "two"])

        self.assertEqual([theme["id"] for theme in themes], ["Sweet"])


class CursorAdapterTests(unittest.TestCase):
    def test_live_value_parser_uses_the_schema_type(self):
        cursor = load_cursor_module()

        self.assertFalse(cursor.parse_live_value(
            {"type": "bool", "default": True}, {"bool": False}
        ))
        self.assertEqual(cursor.parse_live_value(
            {"type": "enum", "default": 2}, {"int": 1}
        ), 1)
        self.assertEqual(cursor.parse_live_value(
            {"type": "int", "default": 24}, {"int": 60}
        ), 60)
        self.assertEqual(cursor.parse_live_value(
            {"type": "float", "default": 1.0}, {"float": 1.5}
        ), 1.5)
        self.assertEqual(cursor.parse_live_value(
            {"type": "string", "default": ""}, {"str": "[[EMPTY]]"}
        ), "")

    def test_protocol_registers_the_cursor_session_methods(self):
        load_cursor_module()
        from lib.ccd import protocol

        self.assertTrue({
            "open_cursor_session",
            "preview_cursor_option",
            "preview_cursor_appearance",
            "keep_cursor_invisible",
            "apply_cursor_settings",
            "close_cursor_session",
        } <= set(protocol.METHODS))

    def test_sidecar_imports_and_shuts_down_cursor_sessions(self):
        entrypoint = (
            Path(__file__).resolve().parents[1] / "lib/ccd/__main__.py"
        ).read_text(encoding="utf-8")

        self.assertIn("cursor,", entrypoint)
        self.assertIn("cursor.shutdown()", entrypoint)


class CursorConfigRenderingTests(unittest.TestCase):
    def test_render_cursor_config_preserves_manual_lua_and_replaces_managed_block(self):
        cursor = load_cursor_module()
        existing = """-- Cursor defaults copied by HCM
hl.config({ cursor = { default_monitor = \"DP-1\" } })

-- --- Cloud Center managed cursor settings ---
hl.config({ cursor = { zoom_factor = 2 } })
-- --- End Cloud Center managed cursor settings ---
"""
        values = {item["key"]: item["default"] for item in cursor.CURSOR_SCHEMA}
        values.update({"zoom_factor": 1.8, "default_monitor": "DP-2"})

        rendered = cursor.render_cursor_config(existing, values)

        self.assertIn('default_monitor = "DP-1"', rendered)
        self.assertEqual(rendered.count(cursor.MANAGED_BEGIN), 1)
        self.assertEqual(rendered.count(cursor.MANAGED_END), 1)
        managed = rendered.split(cursor.MANAGED_BEGIN, 1)[1].split(cursor.MANAGED_END, 1)[0]
        self.assertIn("zoom_factor = 1.8", managed)
        self.assertIn('default_monitor = "DP-2"', managed)
        self.assertNotIn("zoom_factor = 2", managed)

        metadata = next(
            line for line in rendered.splitlines()
            if line.startswith(cursor.STATE_PREFIX)
        )
        state = json.loads(metadata.removeprefix(cursor.STATE_PREFIX))
        self.assertEqual(state["cursor:zoom_factor"], "1.8")
        self.assertEqual(state["cursor:default_monitor"], "DP-2")

    def test_render_cursor_config_escapes_string_values_as_lua_strings(self):
        cursor = load_cursor_module()
        values = {item["key"]: item["default"] for item in cursor.CURSOR_SCHEMA}
        values["default_monitor"] = 'DP-1\"; os.execute("bad")'

        rendered = cursor.render_cursor_config("", values)

        self.assertIn('default_monitor = "DP-1\\\"; os.execute(\\\"bad\\\")"', rendered)

    def test_render_rejects_malformed_or_duplicate_managed_markers(self):
        cursor = load_cursor_module()
        values = {item["key"]: item["default"] for item in cursor.CURSOR_SCHEMA}
        malformed = (
            f"manual\n{cursor.MANAGED_BEGIN}\nmanaged without end\n",
            f"manual\n{cursor.MANAGED_END}\n",
            (
                f"{cursor.MANAGED_BEGIN}\none\n{cursor.MANAGED_END}\n"
                f"{cursor.MANAGED_BEGIN}\ntwo\n{cursor.MANAGED_END}\n"
            ),
        )

        for existing in malformed:
            with self.subTest(existing=existing):
                with self.assertRaisesRegex(ValueError, "managed cursor markers"):
                    cursor.render_cursor_config(existing, values)

    def test_merge_cursor_environment_replaces_both_cursor_systems(self):
        cursor = load_cursor_module()
        existing = [
            {"name": "LIBVA_DRIVER_NAME", "value": "nvidia"},
            {"name": "XCURSOR_THEME", "value": "Afterglow"},
            {"name": "XCURSOR_SIZE", "value": "24"},
            {"name": "HYPRCURSOR_THEME", "value": "Old"},
            {"name": "HYPRCURSOR_SIZE", "value": "16"},
        ]

        merged = cursor.merge_cursor_environment(
            existing, "Bibata-Modern-Ice", 32,
        )

        self.assertEqual(merged, [
            {"name": "LIBVA_DRIVER_NAME", "value": "nvidia"},
            {"name": "XCURSOR_THEME", "value": "Bibata-Modern-Ice"},
            {"name": "XCURSOR_SIZE", "value": "32"},
            {"name": "HYPRCURSOR_THEME", "value": "Bibata-Modern-Ice"},
            {"name": "HYPRCURSOR_SIZE", "value": "32"},
        ])

    def test_apple_hyprcursor_names_map_to_matching_xcursor_themes(self):
        cursor = load_cursor_module()

        self.assertEqual(cursor.xcursor_theme_for("macOS-hypr"), "macOS")
        self.assertEqual(cursor.xcursor_theme_for("macOS-hypr_white"), "macOS-White")
        self.assertEqual(
            cursor.xcursor_theme_for("Bibata-Modern-Ice"),
            "Bibata-Modern-Ice",
        )


class FakeTimer:
    def __init__(self, _delay, callback):
        self.callback = callback
        self.started = False
        self.cancelled = False

    def start(self):
        self.started = True

    def cancel(self):
        self.cancelled = True

    def fire(self):
        if not self.cancelled:
            self.callback()


class CursorSessionTests(unittest.TestCase):
    def setUp(self):
        self.cursor = load_cursor_module()
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.cursor_path = self.root / "user-configs" / "user_cursor.lua"
        self.variables_path = self.root / "user-configs" / "user_variables.lua"
        self.main_path = self.root / "hyprland.lua"
        self.cursor_path.parent.mkdir(parents=True)
        self.cursor_path.write_text("cursor-original\n", encoding="utf-8")
        self.variables_path.write_text("variables-original\n", encoding="utf-8")
        self.main_path.write_text("main-original\n", encoding="utf-8")
        self.values = {
            item["key"]: item["default"] for item in self.cursor.CURSOR_SCHEMA
        }
        self.live = dict(self.values)
        self.theme = "Sweet-cursors"
        self.size = 24
        self.option_calls = []
        self.theme_calls = []
        self.events = []
        self.timers = []

    def tearDown(self):
        self.temporary.cleanup()

    def make_session(self, **overrides):
        def apply_option(key, value):
            self.option_calls.append((key, value))
            self.live[key] = value
            return True, "ok"

        def apply_theme(theme, size):
            self.theme_calls.append((theme, size))
            self.theme = theme
            self.size = size
            return True, "ok"

        def timer_factory(delay, callback):
            timer = FakeTimer(delay, callback)
            self.timers.append(timer)
            return timer

        def persist_cursor(values):
            self.cursor_path.write_text(
                self.cursor.render_cursor_config(
                    self.cursor_path.read_text(encoding="utf-8"), values,
                ),
                encoding="utf-8",
            )

        def persist_environment(theme, size):
            self.variables_path.write_text(
                f"theme={theme}\nsize={size}\n", encoding="utf-8"
            )

        kwargs = dict(
            cursor_path=self.cursor_path,
            variables_path=self.variables_path,
            main_path=self.main_path,
            fetch_values=lambda: dict(self.live),
            fetch_appearance=lambda: (self.theme, self.size),
            fetch_themes=lambda: [{"id": "Sweet-cursors", "name": "Sweet-cursors", "description": ""}],
            fetch_monitors=lambda: ["DP-1", "DP-2"],
            apply_option=apply_option,
            apply_theme=apply_theme,
            activate_cursor=lambda: (True, "ok"),
            persist_cursor=persist_cursor,
            persist_environment=persist_environment,
            timer_factory=timer_factory,
            token_factory=lambda: "cursor-token",
            event_sender=self.events.append,
            clock=lambda: 100.0,
        )
        kwargs.update(overrides)
        return self.cursor.CursorSession(**kwargs)

    def test_open_returns_live_state_without_writing_files(self):
        session = self.make_session()
        before = self.cursor_path.read_bytes()

        result = session.open()

        self.assertTrue(result["ok"])
        self.assertEqual(result["values"], self.values)
        self.assertEqual(result["theme"], "Sweet-cursors")
        self.assertEqual(result["size"], 24)
        self.assertEqual(result["monitors"], ["DP-1", "DP-2"])
        self.assertEqual(self.cursor_path.read_bytes(), before)

    def test_preview_changes_live_state_but_not_disk(self):
        session = self.make_session()
        session.open()
        before = self.cursor_path.read_bytes()

        result = session.preview_option("zoom_factor", 1.8)

        self.assertTrue(result["ok"])
        self.assertEqual(self.option_calls, [("zoom_factor", 1.8)])
        self.assertEqual(result["value"], 1.8)
        self.assertEqual(self.cursor_path.read_bytes(), before)

    def test_failed_preview_restores_the_previous_draft_value(self):
        def reject(_key, _value):
            return False, "invalid cursor value"

        session = self.make_session(apply_option=reject)
        session.open()

        result = session.preview_option("zoom_factor", 1.8)

        self.assertFalse(result["ok"])
        self.assertEqual(result["value"], 1.0)
        self.assertEqual(result["message"], "invalid cursor value")

    def test_preview_theme_is_live_only_until_apply(self):
        session = self.make_session()
        session.open()
        before = self.variables_path.read_bytes()

        result = session.preview_appearance("Other", 32)

        self.assertTrue(result["ok"])
        self.assertEqual(self.theme_calls, [("Other", 32)])
        self.assertEqual(self.variables_path.read_bytes(), before)

    def test_close_reverts_all_unapplied_live_changes(self):
        session = self.make_session()
        session.open()
        session.preview_option("zoom_factor", 1.8)
        session.preview_appearance("Other", 32)
        self.option_calls.clear()
        self.theme_calls.clear()

        result = session.close()

        self.assertTrue(result["ok"])
        self.assertEqual(self.option_calls, [("zoom_factor", 1.0)])
        self.assertEqual(self.theme_calls, [("Sweet-cursors", 24)])

    def test_failed_close_retains_session_so_rollback_can_be_retried(self):
        reject_restore = {"enabled": True}

        def apply_option(key, value):
            if reject_restore["enabled"] and key == "zoom_factor" and value == 1.0:
                return False, "Hyprland unavailable"
            self.live[key] = value
            return True, "ok"

        session = self.make_session(apply_option=apply_option)
        session.open()
        session.preview_option("zoom_factor", 1.8)

        failed = session.close()

        self.assertFalse(failed["ok"])
        self.assertTrue(session.is_open)
        self.assertEqual(session.draft_values["zoom_factor"], 1.8)

        reject_restore["enabled"] = False
        retried = session.close()
        self.assertTrue(retried["ok"])
        self.assertFalse(session.is_open)

    def test_failed_close_does_not_cancel_invisible_safety_timer(self):
        def apply_option(key, value):
            if key == "invisible" and value is False:
                return False, "Hyprland unavailable"
            self.live[key] = value
            return True, "ok"

        session = self.make_session(apply_option=apply_option)
        session.open()
        session.preview_option("invisible", True)
        timer = self.timers[0]

        result = session.close()

        self.assertFalse(result["ok"])
        self.assertFalse(timer.cancelled)
        self.assertEqual(session.invisible_token, "cursor-token")

    def test_open_refuses_to_replace_a_session_whose_rollback_failed(self):
        def apply_option(key, value):
            if key == "zoom_factor" and value == 1.0:
                return False, "Hyprland unavailable"
            self.live[key] = value
            return True, "ok"

        session = self.make_session(apply_option=apply_option)
        session.open()
        session.preview_option("zoom_factor", 1.8)

        result = session.open()

        self.assertFalse(result["ok"])
        self.assertTrue(session.is_open)
        self.assertEqual(session.draft_values["zoom_factor"], 1.8)

    def test_apply_persists_and_advances_the_live_baseline(self):
        session = self.make_session()
        session.open()
        session.preview_option("zoom_factor", 1.8)
        session.preview_appearance("Other", 32)

        result = session.apply()
        self.option_calls.clear()
        self.theme_calls.clear()
        session.close()

        self.assertTrue(result["ok"])
        self.assertIn("zoom_factor = 1.8", self.cursor_path.read_text(encoding="utf-8"))
        self.assertEqual(
            self.variables_path.read_text(encoding="utf-8"),
            "theme=Other\nsize=32\n",
        )
        self.assertEqual(self.option_calls, [])
        self.assertEqual(self.theme_calls, [])

    def test_apply_refuses_to_overwrite_external_changes(self):
        persist_cursor = mock.Mock()
        session = self.make_session(persist_cursor=persist_cursor)
        session.open()
        session.preview_option("zoom_factor", 1.8)
        self.cursor_path.write_text("changed externally\n", encoding="utf-8")

        result = session.apply()

        self.assertFalse(result["ok"])
        self.assertEqual(result["reason"], "external_change")
        persist_cursor.assert_not_called()

    def test_persistence_failure_restores_every_file_and_live_state(self):
        def fail_environment(_theme, _size):
            self.variables_path.write_text("partial\n", encoding="utf-8")
            self.main_path.write_text("changed\n", encoding="utf-8")
            raise OSError("disk full")

        session = self.make_session(persist_environment=fail_environment)
        session.open()
        session.preview_option("zoom_factor", 1.8)
        self.option_calls.clear()

        result = session.apply()

        self.assertFalse(result["ok"])
        self.assertEqual(result["values"], self.values)
        self.assertEqual(result["theme"], "Sweet-cursors")
        self.assertEqual(result["size"], 24)
        self.assertEqual(self.cursor_path.read_text(encoding="utf-8"), "cursor-original\n")
        self.assertEqual(self.variables_path.read_text(encoding="utf-8"), "variables-original\n")
        self.assertEqual(self.main_path.read_text(encoding="utf-8"), "main-original\n")
        self.assertEqual(self.option_calls, [("zoom_factor", 1.0)])

    def test_apply_retains_draft_when_live_rollback_fails_so_close_can_retry(self):
        reject_restore = {"enabled": True}

        def apply_option(key, value):
            if reject_restore["enabled"] and key == "zoom_factor" and value == 1.0:
                return False, "Hyprland unavailable"
            self.live[key] = value
            return True, "ok"

        def fail_environment(_theme, _size):
            raise OSError("disk full")

        session = self.make_session(
            apply_option=apply_option,
            persist_environment=fail_environment,
        )
        session.open()
        session.preview_option("zoom_factor", 1.8)

        failed = session.apply()

        self.assertFalse(failed["ok"])
        self.assertTrue(failed["dirty"])
        self.assertEqual(failed["values"]["zoom_factor"], 1.8)
        self.assertEqual(session.draft_values["zoom_factor"], 1.8)

        reject_restore["enabled"] = False
        retried = session.close()
        self.assertTrue(retried["ok"])
        self.assertEqual(self.live["zoom_factor"], 1.0)

    def test_persistence_failure_restores_additional_migration_files(self):
        legacy_path = self.cursor_path.parent / "user_rules_startup.lua"
        windowrules_path = self.cursor_path.parent / "user_windowrules.lua"
        autostart_path = self.cursor_path.parent / "user_autostart.lua"
        legacy_path.write_text("legacy-original\n", encoding="utf-8")
        windowrules_path.write_text("rules-original\n", encoding="utf-8")
        autostart_path.write_text("autostart-original\n", encoding="utf-8")

        def fail_after_migration(_theme, _size):
            legacy_path.unlink()
            windowrules_path.write_text("rules-migrated\n", encoding="utf-8")
            autostart_path.write_text("autostart-migrated\n", encoding="utf-8")
            raise OSError("disk full")

        session = self.make_session(
            persist_environment=fail_after_migration,
            additional_paths=(legacy_path, windowrules_path, autostart_path),
        )
        session.open()
        session.preview_option("zoom_factor", 1.8)

        result = session.apply()

        self.assertFalse(result["ok"])
        self.assertEqual(legacy_path.read_text(encoding="utf-8"), "legacy-original\n")
        self.assertEqual(windowrules_path.read_text(encoding="utf-8"), "rules-original\n")
        self.assertEqual(autostart_path.read_text(encoding="utf-8"), "autostart-original\n")

    def test_invisible_preview_starts_confirmation_and_timeout_restores_visibility(self):
        session = self.make_session()
        session.open()

        result = session.preview_option("invisible", True)

        self.assertTrue(result["confirmation_required"])
        self.assertEqual(result["token"], "cursor-token")
        self.assertEqual(result["deadline"], 115.0)
        self.assertTrue(self.timers[0].started)
        self.timers[0].fire()
        self.assertEqual(self.option_calls[-1], ("invisible", False))
        self.assertEqual(self.events[-1]["event"], "cursor_visibility")
        self.assertEqual(self.events[-1]["state"], "reverted")

    def test_apply_waits_for_invisible_confirmation(self):
        session = self.make_session()
        session.open()
        session.preview_option("invisible", True)

        blocked = session.apply()
        kept = session.keep_invisible("cursor-token")
        applied = session.apply()

        self.assertFalse(blocked["ok"])
        self.assertTrue(kept["ok"])
        self.assertTrue(applied["ok"])


if __name__ == "__main__":
    unittest.main()
