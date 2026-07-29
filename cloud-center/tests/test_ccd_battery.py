import importlib
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

from lib.ccd import protocol


class CcdBatteryTests(unittest.TestCase):
    def setUp(self):
        self.battery = importlib.import_module("lib.ccd.battery")
        self.battery = importlib.reload(self.battery)

    def tearDown(self):
        self.battery.shutdown()

    def test_methods_are_registered(self):
        expected = {
            "get_battery_snapshot",
            "start_battery_watch",
            "stop_battery_watch",
            "run_battery_action",
        }
        self.assertTrue(expected <= protocol.METHODS.keys())

    def test_sidecar_imports_and_shuts_down_battery(self):
        entrypoint = (
            Path(__file__).resolve().parents[1] / "lib/ccd/__main__.py"
        ).read_text(encoding="utf-8")
        self.assertIn("battery,", entrypoint)
        self.assertIn("battery.shutdown()", entrypoint)

    def test_unknown_action_rejected(self):
        with mock.patch.object(self.battery, "_action_worker") as worker:
            with self.assertRaisesRegex(ValueError, "unknown battery action"):
                self.battery.run_battery_action({
                    "action": "explode", "value": 1, "action_id": "1",
                })
        worker.submit.assert_not_called()

    def test_action_requires_action_id(self):
        with mock.patch.object(self.battery, "_get_action_worker") as get_worker:
            with self.assertRaisesRegex(ValueError, "action_id"):
                self.battery.run_battery_action({
                    "action": "set_threshold", "value": 80,
                })
            get_worker.assert_not_called()

    def test_snapshot_loader_uses_core(self):
        fake = {"present": False, "capabilities": {}, "info": None}
        self.battery._snapshots.loader = lambda: fake
        snap = self.battery.load_snapshot()
        self.assertFalse(snap["present"])
        self.assertFalse(snap["stale"])
        self.assertIn("revision", snap)

    def test_watcher_emits_snapshot(self):
        events = []
        done = threading.Event()

        def emit(snapshot):
            events.append(snapshot)
            done.set()

        watcher = self.battery.BatteryWatcher(
            interval=0.05,
            emitter=emit,
            loader=lambda: {"present": False, "revision": 1},
        )
        watcher.start()
        self.assertTrue(done.wait(1.0))
        self.assertTrue(watcher.stop())
        self.assertGreaterEqual(len(events), 1)


if __name__ == "__main__":
    unittest.main()
