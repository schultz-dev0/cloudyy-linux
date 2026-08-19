from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from lib import island_integrations_core as core


DEFAULTS = {
    "version": 1,
    "order": ["notifications", "timer", "media", "agents"],
    "enabled": {
        "notifications": True,
        "timer": True,
        "media": True,
        "agents": True,
    },
}


class IslandIntegrationsCoreTests(unittest.TestCase):
    def test_defaults_are_independent(self):
        first = core.default_settings()
        first["order"].reverse()
        first["enabled"]["timer"] = False
        self.assertEqual(core.default_settings(), DEFAULTS)

    def test_normalize_removes_unknown_duplicates_and_appends_missing_ids(self):
        value = {
            "version": 1,
            "order": ["media", "future", "media", "notifications"],
            "enabled": {
                "notifications": False,
                "timer": True,
                "media": True,
                "agents": False,
                "future": False,
            },
        }
        self.assertEqual(core.normalize_settings(value), {
            "version": 1,
            "order": ["media", "notifications", "timer", "agents"],
            "enabled": {
                "notifications": False,
                "timer": True,
                "media": True,
                "agents": False,
            },
        })

    def test_invalid_live_values_retain_last_valid(self):
        previous = {
            "version": 1,
            "order": ["agents", "media", "timer", "notifications"],
            "enabled": {
                "notifications": True,
                "timer": False,
                "media": True,
                "agents": True,
            },
        }
        invalid_values = [
            None,
            [],
            {"version": 2, "order": [], "enabled": {}},
            {"version": True, "order": [], "enabled": {}},
            {"version": 1, "order": "media", "enabled": {}},
            {"version": 1, "order": ["media", 7], "enabled": {}},
            {"version": 1, "order": [], "enabled": []},
            {"version": 1, "order": [], "enabled": {"media": 1}},
            {"version": 1, "order": [], "enabled": {"media": "yes"}},
        ]
        for value in invalid_values:
            with self.subTest(value=value):
                self.assertEqual(core.normalize_settings(value, previous), previous)
                self.assertIsNot(core.normalize_settings(value, previous), previous)

    def test_missing_enabled_values_default_to_enabled_and_all_disabled_is_valid(self):
        self.assertEqual(
            core.normalize_settings({"version": 1, "order": [], "enabled": {}}),
            DEFAULTS,
        )
        disabled = {
            "version": 1,
            "order": ["agents"],
            "enabled": {integration_id: False for integration_id in DEFAULTS["order"]},
        }
        normalized = core.normalize_settings(disabled)
        self.assertEqual(normalized["order"], ["agents", "notifications", "timer", "media"])
        self.assertFalse(any(normalized["enabled"].values()))

    def test_missing_file_uses_defaults_without_creating_it(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "island-integrations.json"
            self.assertEqual(core.load_settings(path), DEFAULTS)
            self.assertFalse(path.exists())

    def test_malformed_file_uses_defaults_without_rewriting_it(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "island-integrations.json"
            malformed = b'{"version": 1, broken'
            path.write_bytes(malformed)
            self.assertEqual(core.load_settings(path), DEFAULTS)
            self.assertEqual(path.read_bytes(), malformed)

    def test_invalid_document_file_uses_defaults_without_rewriting_it(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "island-integrations.json"
            original = '{"version":2,"order":[],"enabled":{}}\n'
            path.write_text(original, encoding="utf-8")
            self.assertEqual(core.load_settings(path), DEFAULTS)
            self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_save_rejects_invalid_edits_without_touching_existing_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "island-integrations.json"
            original = '{"keep":"me"}\n'
            path.write_text(original, encoding="utf-8")
            with self.assertRaises(ValueError):
                core.save_settings(path, {"version": 1, "order": [], "enabled": {"timer": 1}})
            self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_save_normalizes_explicit_valid_edit_and_replaces_atomically(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "nested" / "island-integrations.json"
            saved = core.save_settings(path, {
                "version": 1,
                "order": ["agents", "future", "agents"],
                "enabled": {"agents": False, "future": True},
            })
            self.assertEqual(saved["order"], ["agents", "notifications", "timer", "media"])
            self.assertFalse(saved["enabled"]["agents"])
            self.assertTrue(saved["enabled"]["media"])
            self.assertEqual(json.loads(path.read_text(encoding="utf-8")), saved)
            self.assertEqual(list(path.parent.glob(".island-integrations.*")), [])


if __name__ == "__main__":
    unittest.main()
