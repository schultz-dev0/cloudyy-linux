import importlib
import unittest
from unittest import mock


class CcdBezierTests(unittest.TestCase):
    def setUp(self):
        self.mod = importlib.import_module("lib.ccd.bezier")
        self.mod = importlib.reload(self.mod)

    def test_methods_registered(self):
        from lib.ccd import protocol
        for name in (
            "list_bezier_curves",
            "save_bezier_curve",
            "delete_bezier_curve",
            "apply_bezier_curve",
        ):
            self.assertIn(name, protocol.METHODS)

    def test_sidecar_imports_bezier(self):
        path = importlib.import_module("lib.ccd.__main__").__file__
        with open(path, encoding="utf-8") as handle:
            self.assertIn("bezier,", handle.read())

    def test_apply_validates_points(self):
        with self.assertRaisesRegex(ValueError, "points"):
            self.mod.apply_bezier_curve({"name": "x", "points": [1, 2]})


if __name__ == "__main__":
    unittest.main()
