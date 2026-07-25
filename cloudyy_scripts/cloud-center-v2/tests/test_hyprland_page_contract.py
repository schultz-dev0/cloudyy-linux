"""Contract: Hyprland page exposes layout + animation controls."""

from __future__ import annotations

import unittest
from pathlib import Path

CONFIG = Path(__file__).resolve().parents[1] / "config.yaml"


class HyprlandPageContract(unittest.TestCase):
    def setUp(self) -> None:
        self.text = CONFIG.read_text(encoding="utf-8")

    def test_layout_selection(self) -> None:
        self.assertIn("key: hypr/layout", self.text)
        self.assertIn("python3 -m lib.hypr_layout_persist apply general:layout {value}", self.text)
        self.assertIn("- dwindle", self.text)
        self.assertIn("- master", self.text)

    def test_animation_speed(self) -> None:
        self.assertIn("key: hypr/anim_speed", self.text)
        self.assertIn("python3 -m lib.hypr_anim speed {value}", self.text)

    def test_workspace_animation_controls(self) -> None:
        self.assertIn("key: hypr/workspace_anim", self.text)
        self.assertIn("key: hypr/workspace_anim_style", self.text)
        self.assertIn("workspace-enabled true", self.text)
        self.assertIn("workspace-style {value}", self.text)
        self.assertIn("- slidevert", self.text)


if __name__ == "__main__":
    unittest.main()
