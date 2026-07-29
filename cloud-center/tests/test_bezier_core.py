import tempfile
import unittest
from pathlib import Path
from unittest import mock

from lib import bezier_core


class BezierCoreTests(unittest.TestCase):
    def test_ease_linear(self):
        self.assertAlmostEqual(bezier_core.ease(0.5, 0, 0, 1, 1), 0.5, places=3)

    def test_list_includes_builtins_and_chips(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = bezier_core.CurveStore(Path(tmp) / "curves.json")
            result = bezier_core.list_curves(store)
            ids = [c["id"] for c in result["curves"]]
            self.assertIn("easeOutCubic", ids)
            self.assertIn("linear", ids)
            self.assertEqual(result["chips"][1]["label"], "Smooth")
            self.assertTrue(result["next_name"].startswith("myBezier"))

    def test_save_and_delete_user_curve(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "curves.json"
            store = bezier_core.CurveStore(path)
            saved = bezier_core.save_curve("soft", [0.2, 0.8, 0.4, 1.0], store=store)
            self.assertTrue(saved["ok"])
            self.assertTrue(path.exists())
            listed = bezier_core.list_curves(store)
            self.assertTrue(any(c["id"] == "soft" and not c["builtin"] for c in listed["curves"]))
            deleted = bezier_core.delete_curve("soft", store=store)
            self.assertTrue(deleted["ok"])

    def test_cannot_overwrite_builtin(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = bezier_core.CurveStore(Path(tmp) / "curves.json")
            with self.assertRaisesRegex(ValueError, "built-in"):
                bezier_core.save_curve("linear", [0.1, 0.2, 0.3, 0.4], store=store)

    @mock.patch("lib.hypr_animations_persist.apply_animation_key")
    @mock.patch("lib.bezier_core.utility.load_setting", return_value=4)
    def test_apply_calls_hcm(self, _setting, apply_key):
        with tempfile.TemporaryDirectory() as tmp:
            store = bezier_core.CurveStore(Path(tmp) / "curves.json")
            result = bezier_core.apply_curve("mine", [0.2, 0.3, 0.8, 1.0], store=store)
            self.assertTrue(result["ok"])
            self.assertEqual(apply_key.call_count, 2)
            self.assertIn("animations:bezier", apply_key.call_args_list[0].args[0])


if __name__ == "__main__":
    unittest.main()
