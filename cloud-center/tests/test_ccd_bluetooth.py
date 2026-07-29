import importlib
import subprocess
import threading
import unittest
from unittest import mock

from lib.ccd import protocol


class CcdBluetoothTests(unittest.TestCase):
    def setUp(self):
        self.bt = importlib.import_module("lib.ccd.bluetooth")
        self.bt = importlib.reload(self.bt)

    def tearDown(self):
        self.bt.shutdown()

    def test_methods_are_registered(self):
        expected = {
            "get_bluetooth_snapshot",
            "start_bluetooth_watch",
            "stop_bluetooth_watch",
            "run_bluetooth_action",
        }
        self.assertTrue(expected <= protocol.METHODS.keys())

    def test_sidecar_imports_and_shuts_down_bluetooth(self):
        from pathlib import Path

        entrypoint = (
            Path(__file__).resolve().parents[1] / "lib/ccd/__main__.py"
        ).read_text(encoding="utf-8")
        self.assertIn("bluetooth,", entrypoint)
        self.assertIn("bluetooth.shutdown()", entrypoint)

    def test_import_does_not_load_gtk(self):
        import sys

        sys.modules.pop("lib.ccd.bluetooth", None)
        sys.modules.pop("lib.bluetooth_core", None)
        before = set(sys.modules)
        importlib.import_module("lib.ccd.bluetooth")
        loaded = set(sys.modules) - before
        self.assertFalse(any(name == "gi" or name.startswith("gi.") for name in loaded))

    def test_unknown_action_is_rejected_before_queueing(self):
        with mock.patch.object(self.bt, "_action_worker") as worker:
            with self.assertRaisesRegex(ValueError, "unknown bluetooth action"):
                self.bt.run_bluetooth_action({
                    "action": "exec", "target": "x", "value": "bad",
                })
        worker.submit.assert_not_called()

    def test_device_action_requires_known_address(self):
        snapshot = {"devices": [{"address": "AA:BB:CC:DD:EE:FF"}], "powered": True}
        with mock.patch.object(self.bt, "load_snapshot", return_value=snapshot), \
             mock.patch.object(self.bt, "_action_worker") as worker:
            with self.assertRaisesRegex(ValueError, "unknown device"):
                self.bt.run_bluetooth_action({
                    "action": "connect", "target": "00:11:22:33:44:55",
                    "action_id": "one",
                })
        worker.submit.assert_not_called()

    def test_set_power_queues_without_device_target(self):
        snapshot = {"devices": [], "powered": False}
        with mock.patch.object(self.bt, "load_snapshot", return_value=snapshot), \
             mock.patch.object(self.bt, "_action_worker") as worker:
            result = self.bt.run_bluetooth_action({
                "action": "set_power", "target": "adapter", "value": True,
                "action_id": "pwr",
            })
        self.assertTrue(result["queued"])
        worker.submit.assert_called_once()

    def test_action_worker_emits_done_before_authoritative_snapshot(self):
        events = []
        worker = self.bt.BluetoothActionWorker(
            event_sender=events.append,
            executor=mock.Mock(return_value=(True, "")),
            snapshot_loader=mock.Mock(return_value={"revision": 2}),
            start_thread=False,
        )
        worker.process({
            "action_id": "4", "generation": 3, "action": "connect",
            "target": "AA:BB:CC:DD:EE:FF", "value": None,
        })
        self.assertEqual(
            [event["event"] for event in events],
            ["bluetooth_action_done", "bluetooth_snapshot"],
        )

    def test_snapshot_failure_retains_last_snapshot_as_stale(self):
        loader = mock.Mock(side_effect=[
            {"devices": [{"address": "one"}], "powered": True, "scanning": False},
            RuntimeError("bluetoothctl gone"),
        ])
        store = self.bt.SnapshotStore(loader=loader)
        first = store.load()
        second = store.load()
        self.assertFalse(first["stale"])
        self.assertTrue(second["stale"])
        self.assertEqual(second["devices"][0]["address"], "one")
        self.assertIn("bluetoothctl gone", second["error"])

    def test_scan_session_stops_and_reaps_child(self):
        stdin = mock.Mock()
        child = mock.Mock()
        child.stdin = stdin
        child.poll.return_value = None
        child.wait.return_value = 0
        session = self.bt.ScanSession(
            popen=mock.Mock(return_value=child),
            sleeper=lambda _seconds: None,
            duration=0.01,
        )
        ok, message = session.run()
        self.assertTrue(ok)
        self.assertEqual(message, "")
        self.assertEqual(
            [call.args[0] for call in stdin.write.call_args_list],
            ["scan on\n", "scan off\n"],
        )
        child.terminate.assert_called_once()

    def test_scan_session_cancel_skips_remaining_wait(self):
        stdin = mock.Mock()
        child = mock.Mock(stdin=stdin, poll=mock.Mock(return_value=0))
        slept = []
        session = self.bt.ScanSession(
            popen=mock.Mock(return_value=child),
            sleeper=lambda seconds: slept.append(seconds),
            duration=10.0,
        )
        session.request_stop()
        ok, _ = session.run()
        self.assertTrue(ok)
        self.assertLess(sum(slept), 2.0)

    def test_start_scan_uses_session_not_shell_string(self):
        snapshot = {"devices": [], "powered": True, "scanning": False}
        events = []
        session = mock.Mock()
        session.active = False
        session._thread = None

        def start(duration):
            session.active = True
            self.assertEqual(duration, 8.0)
            return True, ""

        session.start = mock.Mock(side_effect=start)
        with mock.patch.object(self.bt, "load_snapshot", return_value=snapshot), \
             mock.patch.object(self.bt, "_get_scan_session", return_value=session):
            worker = self.bt.BluetoothActionWorker(
                event_sender=events.append,
                snapshot_loader=lambda: {**snapshot, "scanning": False},
                start_thread=False,
            )
            worker.process({
                "action_id": "scan", "generation": 1, "action": "start_scan",
                "target": "adapter", "value": 8,
            })
        session.start.assert_called_once_with(8.0)
        self.assertEqual(
            [event["event"] for event in events],
            ["bluetooth_snapshot", "bluetooth_action_done", "bluetooth_snapshot"],
        )
        self.assertTrue(events[1]["ok"])

    def test_stop_bluetooth_watch_stops_scan_session(self):
        watcher = self.bt.BluetoothWatcher()
        session = mock.Mock()
        session.stop.return_value = True
        self.bt._watcher = watcher
        self.bt._scan_session = session
        with mock.patch.object(watcher, "stop", return_value=True):
            result = self.bt.stop_bluetooth_watch({})
        session.stop.assert_called_once()
        self.assertTrue(result["ok"])

    def test_watcher_poll_emits_snapshots_while_requested(self):
        events = []
        emitted = threading.Event()

        def send(event):
            events.append(event)
            if len(events) >= 1:
                emitted.set()

        watcher = self.bt.BluetoothWatcher(
            event_sender=send,
            snapshot_loader=mock.Mock(return_value={"revision": 1, "devices": []}),
            interval=0.01,
        )
        watcher.start()
        self.assertTrue(emitted.wait(timeout=1))
        self.assertTrue(watcher.stop())
        self.assertEqual(events[0]["event"], "bluetooth_snapshot")


if __name__ == "__main__":
    unittest.main()
