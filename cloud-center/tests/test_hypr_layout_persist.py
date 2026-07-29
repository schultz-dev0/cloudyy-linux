import unittest
from pathlib import Path
from unittest import mock

from lib import hcm_lua, hypr_animations_persist as anim, hypr_layout_persist as layout


class TestRenderTable(unittest.TestCase):
    def test_lookandfeel_general_and_decoration_with_subsections(self):
        state = {
            "general:border_size": "1",
            "general:gaps_out": "14",
            "general:gaps_in": "8",
            "general:layout": "dwindle",
            "decoration:rounding": "0",
            "decoration:shadow:enabled": "true",
            "decoration:shadow:range": "1",
            "decoration:blur:enabled": "true",
            "decoration:blur:passes": "3",
            "decoration:blur:size": "3",
        }
        self.assertEqual(
            layout.render_table(state, "lookandfeel"),
            [
                "hl.config({",
                "    general = {",
                "        border_size = 1,",
                "        gaps_out = 14,",
                "        gaps_in = 8,",
                '        layout = "dwindle",',
                "    },",
                "    decoration = {",
                "        rounding = 0,",
                "        shadow = {",
                "            enabled = true,",
                "            range = 1,",
                "        },",
                "        blur = {",
                "            enabled = true,",
                "            passes = 3,",
                "            size = 3,",
                "        },",
                "    },",
                "})",
            ],
        )

    def test_input_with_touchpad_subsection(self):
        state = {
            "input:kb_layout": "gb,ru",
            "input:sensitivity": "0.61",
            "input:touchpad:natural_scroll": "true",
            "input:touchpad:scroll_factor": "1.25",
        }
        self.assertEqual(
            layout.render_table(state, "input"),
            [
                "hl.config({",
                "    input = {",
                '        kb_layout = "gb,ru",',
                "        sensitivity = 0.61,",
                "        touchpad = {",
                "            natural_scroll = true,",
                "            scroll_factor = 1.25,",
                "        },",
                "    },",
                "})",
            ],
        )

    def test_empty_state_renders_nothing(self):
        self.assertEqual(layout.render_table({}, "lookandfeel"), [])
        self.assertEqual(layout.render_table({}, "input"), [])


class TestBuildLiveEval(unittest.TestCase):
    def test_top_level_key(self):
        self.assertEqual(
            layout.build_live_eval("general:border_size", "3"),
            "hl.config({ general = { border_size = 3 } })",
        )

    def test_nested_subsection_key(self):
        self.assertEqual(
            layout.build_live_eval("decoration:shadow:enabled", "true"),
            "hl.config({ decoration = { shadow = { enabled = true } } })",
        )

    def test_unsupported_key_returns_none(self):
        self.assertIsNone(layout.build_live_eval("nonsense", "1"))


class TestApply(unittest.TestCase):
    def _write_fixture(self, path: Path, sentinel: str, marker: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            f'-- @cloud-center-state = {sentinel}\n\n'
            "-- static distro body\n\n"
            f"-- --- Cloud Center managed {marker} settings ---\n"
            f"-- --- End Cloud Center managed {marker} settings ---\n"
        )

    def test_apply_updates_sentinel_and_managed_block(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/layout_apply_test")):
            path = hcm_lua.HYPR_DIR / "lookandfeel.lua"
            self._write_fixture(path, '{"general:gaps_in": "0"}', "lookandfeel")
            with mock.patch.object(layout, "_hyprctl_eval_ok", return_value=True), \
                 mock.patch.object(layout, "_reload_hyprland"):
                layout.apply("general:border_size", "3")

            text = path.read_text()
            self.assertIn('"general:border_size": "3"', text)
            self.assertIn('"general:gaps_in": "0"', text)
            self.assertIn("border_size = 3", text)
            self.assertIn("-- static distro body\n\n", text)  # untouched body preserved
            path.unlink()
            path.parent.rmdir()

    def test_apply_falls_back_to_reload_on_eval_failure(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/layout_apply_test2")):
            path = hcm_lua.HYPR_DIR / "input.lua"
            self._write_fixture(path, "{}", "input")
            with mock.patch.object(layout, "_hyprctl_eval_ok", return_value=False), \
                 mock.patch.object(layout, "_reload_hyprland") as reload_mock:
                layout.apply("input:kb_layout", "gb,ru")
                reload_mock.assert_called_once()
            path.unlink()
            path.parent.rmdir()

    def test_apply_unsupported_key_is_a_noop(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/layout_apply_test3")):
            hcm_lua.HYPR_DIR.mkdir(parents=True, exist_ok=True)
            layout.apply("nonsense:key", "1")  # must not raise
            self.assertFalse((hcm_lua.HYPR_DIR / "lookandfeel.lua").exists())
            hcm_lua.HYPR_DIR.rmdir()


class TestResetPage(unittest.TestCase):
    def _write(self, path: Path, sentinel: str, marker: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            f'-- @cloud-center-state = {sentinel}\n\n'
            f"-- --- Cloud Center managed {marker} settings ---\n"
            f"-- --- End Cloud Center managed {marker} settings ---\n"
        )

    def test_reset_page_input_clears_only_input_keys(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/layout_reset_input_test")):
            path = hcm_lua.HYPR_DIR / "input.lua"
            self._write(path, '{"input:kb_layout": "gb,ru", "input:sensitivity": "0.61"}', "input")
            layout.reset_page("input")
            text = path.read_text()
            self.assertNotIn("kb_layout", text)
            self.assertNotIn("sensitivity", text)
            self.assertEqual(layout._read_state(path), {})
            path.unlink()
            path.parent.rmdir()

    def test_reset_page_hyprland_clears_lookandfeel_and_all_animation_keys(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/layout_reset_hypr_test")):
            lf_path = hcm_lua.HYPR_DIR / "lookandfeel.lua"
            anim_path = hcm_lua.HYPR_DIR / "animations.lua"
            self._write(lf_path, '{"general:gaps_in": "8", "decoration:rounding": "0"}', "lookandfeel")
            anim_path.write_text(
                '-- @cloud-center-state = {"animations:enabled": "true", '
                '"animations:bezier": "x,0,0,1,1", "animations:animation": "windows,1,4,x"}\n\n'
                "-- --- Cloud Center managed animation settings ---\n"
                "-- --- End Cloud Center managed animation settings ---\n"
            )

            layout.reset_page("hyprland")

            lf_text = lf_path.read_text()
            self.assertNotIn("gaps_in", lf_text)
            self.assertNotIn("rounding", lf_text)

            # PAGE_HYPRLAND (persist.rs lines 123-129) clears ALL THREE
            # animations:* keys, not just animations:enabled — a reset
            # button described as removing "all Cloud Center Hyprland
            # visual overrides" must also drop speed/style/bezier state.
            self.assertEqual(anim._read_state(anim_path), {})

            lf_path.unlink()
            anim_path.unlink()
            lf_path.parent.rmdir()

    def test_reset_page_unknown_raises(self):
        with self.assertRaises(ValueError):
            layout.reset_page("nonsense")


if __name__ == "__main__":
    unittest.main()
