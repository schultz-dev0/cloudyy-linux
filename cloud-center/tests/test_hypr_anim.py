"""Unit tests for hypr_anim leaf merge helpers."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from lib import hcm_lua, hypr_anim, hypr_animations_persist, utility


class HyprAnimTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.hypr = root / "hypr"
        self.hypr.mkdir(parents=True)
        self.settings = root / "settings"
        self.settings.mkdir()
        patch = mock.patch.object(utility, "SETTINGS_DIR", self.settings)
        patch.start()
        self.addCleanup(patch.stop)

    def _write_sentinel(self, state: dict[str, str]) -> None:
        path = self.hypr / "animations.lua"
        path.write_text(
            "-- hdr\n"
            f"-- @cloud-center-state = {json.dumps(state)}\n"
            "hl.config({ animations = { enabled = true } })\n",
            encoding="utf-8",
        )

    def test_parse_and_serialize_roundtrip(self) -> None:
        value = "windows,1,4,snap;workspaces,1,3,pro,slidevert"
        specs = hypr_anim.parse_specs(value)
        self.assertEqual(hypr_anim.serialize_specs(specs), value)

    def test_upsert_preserves_other_leaves(self) -> None:
        specs = hypr_anim.parse_specs("windows,1,4,old;workspaces,1,3,pro,slidevert")
        out = hypr_anim.upsert_leaf(specs, "windows", bezier="new", speed=5)
        self.assertEqual(
            hypr_anim.serialize_specs(out),
            "windows,1,5,new;workspaces,1,3,pro,slidevert",
        )

    def test_upsert_adds_workspaces_leaf(self) -> None:
        specs = hypr_anim.parse_specs("windows,1,4,snap")
        out = hypr_anim.upsert_leaf(
            specs, "workspaces", enabled=True, style="fade"
        )
        self.assertEqual(
            hypr_anim.serialize_specs(out),
            "windows,1,4,snap;workspaces,1,4,snap,fade",
        )

    def test_apply_speed_updates_all_leaves(self) -> None:
        self._write_sentinel(
            {
                "animations:animation": "windows,1,4,snap;workspaces,1,4,snap,slidevert",
                "animations:bezier": "snap,0.05,0.9,0.1,1.05",
            }
        )
        with mock.patch.object(hypr_anim, "hcm_apply_animation") as apply:
            apply.return_value = {"ok": True}
            # UI 7 → Hyprland speed 4; UI 10 → Hyprland 1 (fastest)
            hypr_anim.apply_speed(10, hypr_dir=self.hypr)
            apply.assert_called_once_with(
                "windows,1,1,snap;workspaces,1,1,snap,slidevert",
                hypr_dir=self.hypr,
            )
        self.assertEqual(utility.load_setting("hypr/anim_speed", 0), 10)

    def test_ui_to_hypr_speed_inverts(self) -> None:
        self.assertEqual(hypr_anim.ui_to_hypr_speed(10), 1)
        self.assertEqual(hypr_anim.ui_to_hypr_speed(1), 10)
        self.assertEqual(hypr_anim.ui_to_hypr_speed(7), 4)

    def test_workspace_disable_sets_enabled_zero(self) -> None:
        self._write_sentinel(
            {"animations:animation": "windows,1,4,snap"}
        )
        with mock.patch.object(hypr_anim, "hcm_apply_animation") as apply:
            apply.return_value = {"ok": True}
            hypr_anim.apply_workspace_enabled(False, hypr_dir=self.hypr)
            value = apply.call_args.args[0]
            self.assertIn("workspaces,0,", value)
            self.assertIn("windows,1,4,snap", value)


class ReaderWriterRoundTripTest(unittest.TestCase):
    """hypr_anim's reader and hypr_animations_persist's writer must target
    the same ~/.config/hypr/animations.lua — otherwise apply_animation_key
    silently orphans the file the reader still looks at."""

    def test_reader_sees_writer_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            hypr_dir = Path(tmp) / "hypr"
            hypr_dir.mkdir()
            with mock.patch.object(hcm_lua, "HYPR_DIR", hypr_dir):
                with mock.patch.object(hypr_animations_persist, "_hyprctl_eval_ok", return_value=True), \
                     mock.patch.object(hypr_animations_persist, "_reload_hyprland"):
                    hypr_animations_persist.apply_animation_key(
                        "animations:animation", "windows,1,4,snap"
                    )
                self.assertEqual(hypr_anim.current_specs(), [["windows", "1", "4", "snap"]])
                self.assertEqual(hypr_anim.bezier_name(), "snap")


if __name__ == "__main__":
    unittest.main()
