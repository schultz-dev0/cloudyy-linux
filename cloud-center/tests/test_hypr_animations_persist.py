import unittest
from pathlib import Path
from unittest import mock

from lib import hcm_lua, hypr_animations_persist as anim


class TestRenderCurve(unittest.TestCase):
    def test_curve_parses_bouncy(self):
        self.assertEqual(
            anim.render_curve("Bouncy,0.531,-0.817,0.64,1.885"),
            'hl.curve("Bouncy", { type = "bezier", points = { { 0.531, -0.817 }, { 0.64, 1.885 } } })',
        )


class TestRenderAnimation(unittest.TestCase):
    def test_simple_form(self):
        self.assertEqual(
            anim.render_animation("windows,1,4,Bouncy"),
            'hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "Bouncy" })',
        )

    def test_with_style_appends_field(self):
        self.assertEqual(
            anim.render_animation("windows,1,4,Bouncy,slide"),
            'hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "Bouncy", style = "slide" })',
        )

    def test_disabled_speed_zero(self):
        self.assertEqual(
            anim.render_animation("layersOut,0,0"),
            'hl.animation({ leaf = "layersOut", enabled = false, speed = 0 })',
        )


class TestAnimationSpecs(unittest.TestCase):
    def test_splits_semicolon_joined_specs(self):
        self.assertEqual(
            anim.animation_specs("windows,1,4,snap;workspaces,1,3,pro,slidevert"),
            ["windows,1,4,snap", "workspaces,1,3,pro,slidevert"],
        )


class TestApplyAnimationKey(unittest.TestCase):
    def _write_fixture(self, hypr_dir: Path) -> Path:
        path = hypr_dir / "animations.lua"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            '-- @cloud-center-state = {"animations:enabled": "true"}\n\n'
            "hl.config({ animations = { enabled = true } })\n\n"
            "-- --- Cloud Center managed animation settings ---\n"
            "-- --- End Cloud Center managed animation settings ---\n"
        )
        return path

    def test_apply_bezier_updates_managed_block_and_sentinel(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/anim_apply_test")):
            path = self._write_fixture(hcm_lua.HYPR_DIR)
            with mock.patch.object(anim, "_hyprctl_eval_ok", return_value=True), \
                 mock.patch.object(anim, "_reload_hyprland"):
                anim.apply_animation_key("animations:bezier", "Bouncy,0.531,-0.817,0.64,1.885")

            text = path.read_text()
            self.assertIn('"animations:bezier": "Bouncy,0.531,-0.817,0.64,1.885"', text)
            self.assertIn('hl.curve("Bouncy"', text)
            self.assertIn("hl.config({ animations = { enabled = true } })\n\n", text)  # distro body preserved
            path.unlink()
            path.parent.rmdir()

    def test_apply_falls_back_to_reload_on_eval_failure(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/anim_apply_test2")):
            self._write_fixture(hcm_lua.HYPR_DIR)
            with mock.patch.object(anim, "_hyprctl_eval_ok", return_value=False), \
                 mock.patch.object(anim, "_reload_hyprland") as reload_mock:
                anim.apply_animation_key("animations:bezier", "Bouncy,0.531,-0.817,0.64,1.885")
                reload_mock.assert_called_once()
            (hcm_lua.HYPR_DIR / "animations.lua").unlink()
            hcm_lua.HYPR_DIR.rmdir()


class TestClearKey(unittest.TestCase):
    def test_clear_key_removes_only_that_key(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/anim_clear_test")):
            path = hcm_lua.HYPR_DIR / "animations.lua"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                '-- @cloud-center-state = {"animations:enabled": "true", "animations:bezier": "x,0,0,1,1"}\n\n'
                "-- --- Cloud Center managed animation settings ---\n"
                "-- --- End Cloud Center managed animation settings ---\n"
            )
            anim.clear_key("animations:enabled")
            text = path.read_text()
            self.assertNotIn('"animations:enabled"', text)
            self.assertIn('"animations:bezier": "x,0,0,1,1"', text)
            self.assertNotIn("hl.config({ animations = { enabled", text)
            path.unlink()
            path.parent.rmdir()

    def test_clear_key_missing_is_noop(self):
        with mock.patch.object(hcm_lua, "HYPR_DIR", Path("/tmp/anim_clear_test2")):
            path = hcm_lua.HYPR_DIR / "animations.lua"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('-- @cloud-center-state = {"animations:bezier": "x,0,0,1,1"}\n\n')
            before = path.read_text()
            anim.clear_key("animations:enabled")
            self.assertEqual(path.read_text(), before)
            path.unlink()
            path.parent.rmdir()


if __name__ == "__main__":
    unittest.main()
