import importlib
import threading
import unittest
from pathlib import Path
from unittest import mock

from lib.ccd import protocol


class CcdWifiTests(unittest.TestCase):
    def setUp(self):
        self.wifi = importlib.import_module("lib.ccd.wifi")
        self.wifi = importlib.reload(self.wifi)

    def tearDown(self):
        self.wifi.shutdown()

    def test_methods_are_registered_on_import(self):
        expected = {
            "get_wifi_snapshot", "start_wifi_watch", "stop_wifi_watch",
            "run_wifi_action",
        }
        self.assertTrue(expected <= protocol.METHODS.keys())

    def test_sidecar_imports_and_shuts_down_wifi(self):
        entrypoint = (
            Path(__file__).resolve().parents[1] / "lib/ccd/__main__.py"
        ).read_text(encoding="utf-8")
        self.assertIn("wifi,", entrypoint)
        self.assertIn("wifi.shutdown()", entrypoint)

    def test_unknown_action_is_rejected_before_queueing(self):
        with mock.patch.object(self.wifi, "_action_worker") as worker:
            with self.assertRaisesRegex(ValueError, "unknown wifi action"):
                self.wifi.run_wifi_action({
                    "action": "exec", "target": "x", "value": "bad",
                    "action_id": "1",
                })
        worker.submit.assert_not_called()

    def test_action_requires_action_id_and_valid_generation(self):
        with mock.patch.object(self.wifi, "_action_worker") as worker:
            with self.assertRaisesRegex(ValueError, "action_id"):
                self.wifi.run_wifi_action({
                    "action": "rescan", "target": "wifi", "value": None,
                })
            with self.assertRaisesRegex(ValueError, "generation"):
                self.wifi.run_wifi_action({
                    "action": "rescan", "target": "wifi", "value": None,
                    "action_id": "one", "generation": "nope",
                })
        worker.submit.assert_not_called()

    def test_action_worker_emits_done_before_snapshot(self):
        events = []
        worker = self.wifi.WifiActionWorker(
            event_sender=events.append,
            executor=mock.Mock(return_value=(True, "ok")),
            snapshot_loader=mock.Mock(return_value={"revision": 2}),
            start_thread=False,
        )
        worker.process({
            "action_id": "4", "generation": 3, "action": "connect",
            "target": "Home", "value": "secret",
        })
        self.assertEqual(
            [event["event"] for event in events],
            ["wifi_action_done", "wifi_snapshot"],
        )
        self.assertNotIn("secret", str(events))

    def test_action_worker_never_logs_secrets(self):
        events = []
        with self.assertLogs(self.wifi.log.name, level="WARNING") as captured:
            worker = self.wifi.WifiActionWorker(
                event_sender=events.append,
                executor=mock.Mock(side_effect=RuntimeError("boom")),
                snapshot_loader=mock.Mock(return_value={"revision": 1}),
                start_thread=False,
            )
            worker.process({
                "action_id": "9", "generation": 1,
                "action": "connect_enterprise", "target": "Campus",
                "value": {"identity": "user@edu", "password": "top-secret"},
            })
        joined = "\n".join(captured.output)
        self.assertNotIn("top-secret", joined)
        self.assertNotIn("user@edu", joined)

    def test_watcher_polls_without_rescan_by_default(self):
        events = []
        loader = mock.Mock(return_value={"revision": 1, "networks": []})
        watcher = self.wifi.WifiWatcher(
            event_sender=events.append,
            snapshot_loader=loader,
            interval_seconds=0.05,
        )
        watcher.start()
        try:
            deadline = threading.Event()
            deadline.wait(0.2)
        finally:
            self.assertTrue(watcher.stop())
        self.assertGreaterEqual(loader.call_count, 1)
        for call in loader.call_args_list:
            # Default watch refresh must not force nmcli rescan.
            self.assertEqual(call.kwargs.get("rescan", False), False)
        self.assertTrue(any(event["event"] == "wifi_snapshot" for event in events))

    def test_snapshot_failure_retains_last_snapshot_as_stale(self):
        loader = mock.Mock(side_effect=[
            {"enabled": True, "networks": [{"ssid": "Home"}]},
            RuntimeError("nmcli gone"),
        ])
        store = self.wifi.SnapshotStore(loader=loader)
        first = store.load()
        second = store.load()
        self.assertFalse(first["stale"])
        self.assertTrue(second["stale"])
        self.assertEqual(second["networks"][0]["ssid"], "Home")
        self.assertIn("nmcli gone", second["error"])


if __name__ == "__main__":
    unittest.main()
