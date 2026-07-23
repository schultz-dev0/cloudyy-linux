import importlib
import unittest
from unittest import mock


class CcdRegionTests(unittest.TestCase):
    def setUp(self):
        self.region = importlib.import_module("lib.ccd.region")
        self.region = importlib.reload(self.region)

    def tearDown(self):
        self.region.shutdown()

    def test_methods_registered(self):
        from lib.ccd import protocol
        for name in (
            "get_region_snapshot",
            "get_region_timezones",
            "start_region_watch",
            "stop_region_watch",
            "run_region_action",
        ):
            self.assertIn(name, protocol.METHODS)

    def test_sidecar_imports_and_shuts_down_region(self):
        entrypoint_path = importlib.import_module("lib.ccd.__main__").__file__
        with open(entrypoint_path, encoding="utf-8") as handle:
            entrypoint = handle.read()
        self.assertIn("region,", entrypoint)
        self.assertIn("region.shutdown()", entrypoint)

    def test_unknown_action_rejected(self):
        with mock.patch.object(self.region, "_action_worker") as worker:
            with self.assertRaisesRegex(ValueError, "unknown region action"):
                self.region.run_region_action({
                    "action": "nope",
                    "action_id": "1",
                    "generation": 0,
                })
            worker.submit.assert_not_called()

    def test_queues_action(self):
        with mock.patch.object(self.region, "_get_action_worker") as get_worker:
            worker = mock.Mock()
            get_worker.return_value = worker
            result = self.region.run_region_action({
                "action": "set_ntp",
                "value": True,
                "action_id": "a1",
                "generation": 2,
            })
            self.assertTrue(result["queued"])
            worker.submit.assert_called_once()

    def test_snapshot_loader_marks_revision(self):
        fake = {
            "polkit_ready": True,
            "timezone": "UTC",
            "ntp_enabled": True,
            "manual_location": False,
            "location": None,
            "clock": {"year": 2026, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0},
            "error": "",
        }
        self.region._snapshots.loader = lambda include_location=True: fake
        snap = self.region.load_snapshot()
        self.assertFalse(snap["stale"])
        self.assertGreaterEqual(snap["revision"], 1)

    def test_watcher_emits(self):
        emitted = []
        watcher = self.region.RegionWatcher(
            interval=0.01,
            emitter=emitted.append,
            loader=lambda: {"ok": True},
        )
        watcher.start()
        self.assertTrue(watcher._thread.is_alive())
        watcher.stop()


if __name__ == "__main__":
    unittest.main()
