import importlib
import subprocess
import threading
import unittest
from unittest import mock

from lib.ccd import protocol


class CcdAudioTests(unittest.TestCase):
    def setUp(self):
        self.audio = importlib.import_module("lib.ccd.audio")
        self.audio = importlib.reload(self.audio)

    def tearDown(self):
        self.audio.shutdown()

    def test_methods_are_registered(self):
        expected = {
            "get_audio_snapshot", "start_audio_watch", "stop_audio_watch",
            "run_audio_action", "set_audio_automation", "set_audio_priority",
            "enable_audio_autoswitch_service", "get_audio_autoswitch_service_status",
        }
        self.assertTrue(expected <= protocol.METHODS.keys())

    def test_unknown_action_is_rejected_before_queueing(self):
        with mock.patch.object(self.audio, "_action_worker") as worker:
            with self.assertRaisesRegex(ValueError, "unknown audio action"):
                self.audio.run_audio_action({
                    "action": "exec", "target": "x", "value": "bad",
                })
        worker.submit.assert_not_called()

    def test_action_requires_known_target_and_valid_volume(self):
        snapshot = {"sinks": [{"name": "sink.one"}]}
        with mock.patch.object(self.audio, "load_snapshot", return_value=snapshot), \
             mock.patch.object(self.audio, "_action_worker") as worker:
            with self.assertRaisesRegex(ValueError, "unknown output"):
                self.audio.run_audio_action({
                    "action": "set_sink_volume", "target": "missing", "value": 70,
                    "action_id": "one",
                })
            with self.assertRaisesRegex(ValueError, "volume"):
                self.audio.run_audio_action({
                    "action": "set_sink_volume", "target": "sink.one", "value": 151,
                    "action_id": "two",
                })
        worker.submit.assert_not_called()

    def test_action_accepts_a_numeric_action_id(self):
        snapshot = {"sinks": [{"name": "sink.one"}]}
        with mock.patch.object(self.audio, "load_snapshot", return_value=snapshot), \
             mock.patch.object(self.audio, "_action_worker") as worker:
            result = self.audio.run_audio_action({
                "action": "set_sink_volume", "target": "sink.one", "value": 70,
                "action_id": 4,
            })
        self.assertEqual(result["action_id"], "4")
        self.assertEqual(worker.submit.call_args.args[0]["action_id"], "4")

    def test_priority_keeps_offline_names_and_deduplicates(self):
        # Priority remembers preferred outputs across disconnects; only the
        # selection policy skips names that are absent right now.
        sink = mock.Mock()
        sink.name = "sink.one"
        sink.description = "Speakers"
        with mock.patch.object(self.audio.audio_core, "list_sinks", return_value=[sink]), \
             mock.patch.object(self.audio.audio_core, "load_auto_switch_config", return_value={}), \
             mock.patch.object(self.audio.audio_core, "save_auto_switch_config") as save, \
             mock.patch.object(self.audio.service_control, "synchronize_service"), \
             mock.patch.object(self.audio.audio_core, "_bluez_device_name", return_value="Buds"):
            result = self.audio.set_audio_priority({
                "priority": [
                    "bluez_output.offline.1",
                    "sink.one",
                    "bluez_output.offline.1",
                    "sink.one",
                ],
            })
        saved = save.call_args.args[0]
        self.assertEqual(
            saved["output_priority"],
            ["bluez_output.offline.1", "sink.one"],
        )
        self.assertEqual(
            saved["output_priority_labels"],
            {"bluez_output.offline.1": "Buds", "sink.one": "Speakers"},
        )
        self.assertIsInstance(result, dict)

    def test_priority_rejects_empty_or_non_string_names(self):
        with self.assertRaisesRegex(ValueError, "priority must be a list of output names"):
            self.audio.set_audio_priority({"priority": ["sink.one", ""]})
        with self.assertRaisesRegex(ValueError, "priority must be a list of output names"):
            self.audio.set_audio_priority({"priority": ["sink.one", 3]})

    def test_action_worker_emits_done_before_authoritative_snapshot(self):
        events = []
        worker = self.audio.AudioActionWorker(
            event_sender=events.append,
            executor=mock.Mock(return_value=(True, "")),
            snapshot_loader=mock.Mock(return_value={"revision": 2}),
            start_thread=False,
        )
        worker.process({
            "action_id": "4", "generation": 3, "action": "set_sink_volume",
            "target": "sink.one", "value": 70,
        })
        self.assertEqual(
            [event["event"] for event in events],
            ["audio_action_done", "audio_snapshot"],
        )

    def test_snapshot_failure_retains_last_snapshot_as_stale(self):
        loader = mock.Mock(side_effect=[
            {"sinks": [{"name": "one"}]}, RuntimeError("server gone"),
        ])
        store = self.audio.SnapshotStore(loader=loader, service_loader=lambda: {})
        first = store.load()
        second = store.load()
        self.assertFalse(first["stale"])
        self.assertTrue(second["stale"])
        self.assertEqual(second["sinks"][0]["name"], "one")
        self.assertIn("server gone", second["error"])
        self.assertGreater(second["revision"], first["revision"])

    def test_snapshot_store_serializes_concurrent_loads(self):
        first_loader_started = threading.Event()
        allow_first_loader_to_finish = threading.Event()
        second_load_finished = threading.Event()
        calls = 0
        calls_lock = threading.Lock()
        results = []

        def loader(_service):
            nonlocal calls
            with calls_lock:
                calls += 1
                call = calls
            if call == 1:
                first_loader_started.set()
                allow_first_loader_to_finish.wait()
                return {"sinks": [{"name": "old"}]}
            return {"sinks": [{"name": "new"}]}

        store = self.audio.SnapshotStore(loader=loader, service_loader=lambda: {})
        first = threading.Thread(target=lambda: results.append(store.load()))
        first.start()
        self.assertTrue(first_loader_started.wait(timeout=1))

        def load_second():
            results.append(store.load())
            second_load_finished.set()

        second = threading.Thread(target=load_second)
        second.start()
        try:
            self.assertTrue(second_load_finished.wait(timeout=1))
        finally:
            allow_first_loader_to_finish.set()
            first.join(timeout=1)
            second.join(timeout=1)
        with mock.patch.object(store, "loader", side_effect=RuntimeError("gone")):
            stale = store.load()
        self.assertEqual(sorted(result["revision"] for result in results), [1, 2])
        self.assertEqual(stale["sinks"][0]["name"], "new")
        self.assertEqual(stale["revision"], 3)

    def test_invalid_generation_is_rejected_before_queue_submission(self):
        snapshot = {"sinks": [{"name": "sink.one"}]}
        with mock.patch.object(self.audio, "load_snapshot", return_value=snapshot), \
             mock.patch.object(self.audio, "_action_worker") as worker:
            with self.assertRaisesRegex(ValueError, "generation"):
                self.audio.run_audio_action({
                    "action": "set_sink_volume", "target": "sink.one", "value": 70,
                    "action_id": "bad", "generation": "not-a-number",
                })
        worker.submit.assert_not_called()

    def test_malformed_worker_item_does_not_block_later_valid_action(self):
        events = []
        valid_done = threading.Event()

        def send(event):
            events.append(event)
            if event.get("action_id") == "valid":
                valid_done.set()

        executor = mock.Mock(return_value=(True, ""))
        worker = self.audio.AudioActionWorker(
            event_sender=send,
            executor=executor,
            snapshot_loader=mock.Mock(return_value={"revision": 1}),
        )
        worker.submit({
            "action": "set_sink_volume", "target": "sink.one", "value": 70,
            "action_id": "bad", "generation": "not-a-number",
        })
        worker.submit({
            "action": "set_sink_volume", "target": "sink.one", "value": 70,
            "action_id": "valid", "generation": 1,
        })
        self.assertTrue(valid_done.wait(timeout=1))
        worker.shutdown()
        self.assertEqual(executor.call_count, 1)

    def test_watcher_stop_waits_for_an_inflight_snapshot_emit(self):
        watcher = self.audio.AudioWatcher(event_sender=lambda event: events.append(event))
        events = []
        snapshot_started = threading.Event()
        release_snapshot = threading.Event()
        reached_stop = threading.Event()
        stopped = threading.Event()

        def load_snapshot():
            snapshot_started.set()
            release_snapshot.wait(timeout=1)
            return {"revision": 1}

        watcher.requested = True
        callback = threading.Thread(target=watcher._send_debounced_snapshot)
        with mock.patch.object(self.audio, "load_snapshot", side_effect=load_snapshot), \
             mock.patch.object(watcher, "_terminate_child", side_effect=lambda _child: reached_stop.set() or True):
            callback.start()
            self.assertTrue(snapshot_started.wait(timeout=1))

            def stop():
                self.assertTrue(watcher.stop())
                events.append({"event": "stopped"})
                stopped.set()

            stopper = threading.Thread(target=stop)
            stopper.start()
            self.assertTrue(reached_stop.wait(timeout=1))
            self.assertFalse(stopped.wait(timeout=0.1))
            release_snapshot.set()
            self.assertTrue(stopped.wait(timeout=1))
        callback.join(timeout=1)
        stopper.join(timeout=1)
        self.assertEqual([event["event"] for event in events], ["stopped"])

    def test_watcher_stop_times_out_when_an_external_emit_is_stuck(self):
        watcher = self.audio.AudioWatcher(event_sender=mock.Mock())
        snapshot_started = threading.Event()
        release_snapshot = threading.Event()
        finished = threading.Event()
        result = []

        def load_snapshot():
            snapshot_started.set()
            release_snapshot.wait(timeout=1)
            return {"revision": 1}

        watcher.requested = True
        callback = threading.Thread(target=watcher._send_debounced_snapshot)
        with mock.patch.object(self.audio, "load_snapshot", side_effect=load_snapshot), \
             mock.patch.object(self.audio, "SHUTDOWN_TIMEOUT_SECONDS", 0.05):
            callback.start()
            self.assertTrue(snapshot_started.wait(timeout=1))

            def stop():
                result.append(watcher.stop())
                finished.set()

            stopper = threading.Thread(target=stop)
            stopper.start()
            try:
                self.assertTrue(finished.wait(timeout=0.5))
                self.assertEqual(result, [False])
            finally:
                release_snapshot.set()
                callback.join(timeout=1)
                stopper.join(timeout=1)
        self.assertTrue(watcher.stop())

    def test_watcher_reports_child_reaping_timeout(self):
        child = mock.Mock()
        child.poll.return_value = None
        child.wait.side_effect = [
            subprocess.TimeoutExpired("pactl", 0.01),
            subprocess.TimeoutExpired("pactl", 0.01),
        ]
        watcher = self.audio.AudioWatcher()
        self.assertIs(watcher._terminate_child(child), False)
        child.terminate.assert_called_once()
        child.kill.assert_called_once()

    def test_watcher_stop_fails_when_its_subscription_thread_survives_join(self):
        watcher = self.audio.AudioWatcher()
        thread = mock.Mock()
        thread.is_alive.return_value = True
        watcher.thread = thread
        with mock.patch.object(watcher, "_terminate_child", return_value=True):
            self.assertFalse(watcher.stop())
        thread.join.assert_called_once_with(timeout=self.audio.SHUTDOWN_TIMEOUT_SECONDS)

    def test_stop_audio_watch_reports_watcher_shutdown_failure(self):
        watcher = self.audio.AudioWatcher()
        self.audio._watcher = watcher
        with mock.patch.object(watcher, "stop", return_value=False):
            result = self.audio.stop_audio_watch({})
        self.assertEqual(result, {
            "ok": False,
            "message": "Audio watcher is still stopping",
        })

    def test_watcher_startup_reaps_after_releasing_its_state_lock(self):
        watcher = self.audio.AudioWatcher()
        child = mock.Mock(stdout=[])
        lock_was_available = []

        def popen(*_args, **_kwargs):
            with watcher._lock:
                watcher.requested = False
            return child

        def terminate(_child):
            def probe_lock():
                acquired = watcher._lock.acquire(blocking=False)
                lock_was_available.append(acquired)
                if acquired:
                    watcher._lock.release()

            probe = threading.Thread(target=probe_lock)
            probe.start()
            probe.join(timeout=1)

        watcher.requested = True
        watcher.popen = popen
        with mock.patch.object(watcher, "_terminate_child", side_effect=terminate):
            watcher._run()
        self.assertEqual(lock_was_available, [True])

    def test_watcher_start_is_idempotent_and_restarts_once(self):
        watcher = self.audio.AudioWatcher(popen=mock.Mock(), event_sender=mock.Mock())
        watcher._run = mock.Mock()
        watcher.start()
        first_thread = watcher.thread
        watcher.start()
        first_thread.join(timeout=1)
        self.assertIs(watcher.thread, first_thread)
        watcher._run.assert_called_once()

        watcher._unexpected_exit()
        self.assertEqual(watcher._restart_count, 1)
        watcher._unexpected_exit()
        self.assertIn("stopped", watcher.warning)
        watcher.stop()

    def test_automation_saves_and_synchronizes_service(self):
        with mock.patch.object(self.audio.audio_core, "load_auto_switch_config", return_value={"extra": 1}), \
             mock.patch.object(self.audio.audio_core, "save_auto_switch_config") as save, \
             mock.patch.object(self.audio.service_control, "synchronize_service", return_value={"ok": True}), \
             mock.patch.object(self.audio, "load_snapshot", return_value={"revision": 1}):
            result = self.audio.set_audio_automation({"enabled": True})
        self.assertTrue(save.call_args.args[0]["enabled"])
        self.assertEqual(save.call_args.args[0]["extra"], 1)
        self.assertEqual(result["revision"], 1)

    def test_not_now_dismisses_prompt_without_disabling_service(self):
        with mock.patch.object(self.audio.audio_core, "load_auto_switch_config", return_value={}), \
             mock.patch.object(self.audio.audio_core, "save_auto_switch_config") as save, \
             mock.patch.object(self.audio.service_control, "set_service_enabled") as enable, \
             mock.patch.object(self.audio.service_control, "dismiss_service_prompt", return_value={"service_prompt_version": 1}), \
             mock.patch.object(self.audio.service_control, "service_status", return_value={"active": True}), \
             mock.patch.object(self.audio, "load_snapshot", return_value={"revision": 1}), \
             mock.patch.object(self.audio.protocol, "send_event"):
            result = self.audio.enable_audio_autoswitch_service({"enable": False, "dismiss_prompt": True})
        enable.assert_not_called()
        save.assert_called_once_with({"service_prompt_version": 1})
        self.assertTrue(result["status"]["active"])


if __name__ == "__main__":
    unittest.main()
