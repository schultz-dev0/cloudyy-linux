from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from lib.ccd import protocol


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


class IslandIntegrationsProtocolTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.environment = mock.patch.dict(
            os.environ, {"XDG_CONFIG_HOME": self.temporary.name}, clear=False,
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)

        # The sidecar entrypoint owns registration of every CCD concern.
        from lib.ccd import __main__  # noqa: F401

        self.path = (
            Path(self.temporary.name)
            / "cloud-center/settings/quickshell/island-integrations.json"
        )

    def request(self, request_id: int, method: str, params: dict | None = None) -> dict:
        return protocol.handle_line(json.dumps({
            "id": request_id,
            "method": method,
            "params": params or {},
        }))

    def test_get_missing_settings_returns_defaults_without_creating_file(self):
        reply = self.request(1, "get_island_integrations")

        self.assertEqual(reply, {"id": 1, "ok": True, "result": DEFAULTS})
        self.assertFalse(self.path.exists())

    def test_save_returns_exact_normalized_document_and_get_round_trips_it(self):
        edit = {
            "version": 1,
            "order": ["agents", "future", "agents", "notifications"],
            "enabled": {"agents": False, "notifications": False, "future": True},
        }
        expected = {
            "version": 1,
            "order": ["agents", "notifications", "timer", "media"],
            "enabled": {
                "notifications": False,
                "timer": True,
                "media": True,
                "agents": False,
            },
        }

        saved = self.request(2, "save_island_integrations", {"settings": edit})
        loaded = self.request(3, "get_island_integrations")

        self.assertEqual(saved, {"id": 2, "ok": True, "result": expected})
        self.assertEqual(loaded, {"id": 3, "ok": True, "result": expected})
        self.assertEqual(json.loads(self.path.read_text(encoding="utf-8")), expected)

    def test_get_corrupt_file_returns_defaults_and_preserves_exact_bytes(self):
        self.path.parent.mkdir(parents=True)
        original = b'{"version": 1, broken\xff'
        self.path.write_bytes(original)

        reply = self.request(4, "get_island_integrations")

        self.assertEqual(reply, {"id": 4, "ok": True, "result": DEFAULTS})
        self.assertEqual(self.path.read_bytes(), original)

    def test_unsupported_version_returns_error_without_overwriting_file(self):
        self.path.parent.mkdir(parents=True)
        original = b'{"keep":"existing"}\n'
        self.path.write_bytes(original)

        reply = self.request(5, "save_island_integrations", {
            "settings": {"version": 2, "order": [], "enabled": {}},
        })

        self.assertEqual(reply, {
            "id": 5,
            "ok": False,
            "error": "invalid Island integration settings",
        })
        self.assertEqual(self.path.read_bytes(), original)

    def test_invalid_top_level_params_return_stable_error_without_overwriting_file(self):
        self.path.parent.mkdir(parents=True)
        original = b'{"keep":"existing"}\n'
        self.path.write_bytes(original)
        cases = [
            {"params": [1]},
            {"params": "invalid"},
            {"params": 7},
            {"params": None},
            {},
        ]

        for request_id, case in enumerate(cases, 20):
            with self.subTest(params=case.get("params", "missing")):
                request = {
                    "id": request_id,
                    "method": "save_island_integrations",
                    **case,
                }
                reply = protocol.handle_line(json.dumps(request))

                self.assertEqual(reply, {
                    "id": request_id,
                    "ok": False,
                    "error": "invalid Island integration settings",
                })
                self.assertEqual(self.path.read_bytes(), original)

    def test_save_accepts_all_integrations_disabled(self):
        edit = {
            "version": 1,
            "order": ["media", "agents", "timer", "notifications"],
            "enabled": {
                "notifications": False,
                "timer": False,
                "media": False,
                "agents": False,
            },
        }

        reply = self.request(6, "save_island_integrations", {"settings": edit})

        self.assertEqual(reply, {"id": 6, "ok": True, "result": edit})
        self.assertEqual(json.loads(self.path.read_text(encoding="utf-8")), edit)

    def test_atomic_replace_failure_returns_ccd_error_and_preserves_previous_file(self):
        from lib import island_integrations_core as core

        self.path.parent.mkdir(parents=True)
        original = b'{"keep":"previous"}\n'
        self.path.write_bytes(original)
        edit = {"version": 1, "order": [], "enabled": {}}

        with mock.patch.object(core.Path, "replace", side_effect=OSError("replace failed")):
            reply = self.request(7, "save_island_integrations", {"settings": edit})

        self.assertEqual(reply, {
            "id": 7,
            "ok": False,
            "error": "Could not save Island integration settings",
        })
        self.assertEqual(self.path.read_bytes(), original)
        self.assertEqual(list(self.path.parent.glob(".island-integrations.*")), [])


class BackendWrapperContractTests(unittest.TestCase):
    def test_island_methods_forward_success_and_error_callbacks(self):
        backend = (
            Path(__file__).resolve().parents[2]
            / ".config/quickshell/cloud-center/services/Backend.qml"
        ).read_text(encoding="utf-8")

        self.assertIn(
            'request("get_island_integrations", {}, callback, errorCallback);', backend,
        )
        self.assertIn(
            'request("save_island_integrations", { settings: settings }, callback, errorCallback);',
            backend,
        )


if __name__ == "__main__":
    unittest.main()
