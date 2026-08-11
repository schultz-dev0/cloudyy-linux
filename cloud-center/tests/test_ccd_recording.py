import importlib
import threading
import unittest
from pathlib import Path
from unittest import mock

from lib.ccd import protocol


class CcdRecordingTests(unittest.TestCase):
    def setUp(self):
        self.recording = importlib.import_module("lib.ccd.recording")
        self.recording = importlib.reload(self.recording)

    def tearDown(self):
        self.recording.shutdown()

    def test_methods_are_registered(self):
        expected = {
            "get_recording_snapshot",
            "start_recording_watch",
            "stop_recording_watch",
            "run_recording_action",
        }
        self.assertTrue(expected <= protocol.METHODS.keys())

    def test_sidecar_imports_and_shuts_down_recording(self):
        entrypoint = (
            Path(__file__).resolve().parents[1] / "lib/ccd/__main__.py"
        ).read_text(encoding="utf-8")
        self.assertIn("recording,", entrypoint)
        self.assertIn("recording.shutdown()", entrypoint)

    def test_unknown_action_rejected(self):
        with mock.patch.object(self.recording, "_action_worker") as worker:
            with self.assertRaisesRegex(ValueError, "unknown recording action"):
                self.recording.run_recording_action({
                    "action": "explode", "value": 1, "action_id": "1",
                })
        worker.submit.assert_not_called()

    def test_action_requires_action_id(self):
        with mock.patch.object(self.recording, "_get_action_worker") as get_worker:
            with self.assertRaisesRegex(ValueError, "action_id"):
                self.recording.run_recording_action({
                    "action": "trigger_record_toggle",
                })
            get_worker.assert_not_called()

    def test_run_recording_action_queues_and_returns_action_id(self):
        with mock.patch.object(self.recording, "_get_action_worker") as get_worker:
            result = self.recording.run_recording_action({
                "action": "trigger_screenshot", "value": "ephemeral", "action_id": "42",
            })
        self.assertEqual(result, {"queued": True, "action_id": "42", "generation": 0})
        get_worker.return_value.submit.assert_called_once_with({
            "action": "trigger_screenshot",
            "target": "trigger_screenshot",
            "value": "ephemeral",
            "action_id": "42",
            "generation": 0,
        })

    def test_snapshot_loader_uses_core(self):
        fake = {
            "settings": {}, "audio_inputs": {"mics": [], "desktops": []},
            "recording": {"active": False, "out_file": "", "selection": ""},
            "gallery": [],
        }
        self.recording._snapshots.loader = lambda: fake
        snap = self.recording.load_snapshot()
        self.assertFalse(snap["recording"]["active"])
        self.assertFalse(snap["stale"])
        self.assertIn("revision", snap)

    def test_watcher_emits_snapshot(self):
        events = []
        done = threading.Event()

        def emit(snapshot):
            events.append(snapshot)
            done.set()

        watcher = self.recording.RecordingWatcher(
            interval=0.05,
            emitter=emit,
            loader=lambda: {"recording": {"active": False}, "revision": 1},
        )
        watcher.start()
        self.assertTrue(done.wait(1.0))
        self.assertTrue(watcher.stop())
        self.assertGreaterEqual(len(events), 1)

    def test_set_setting_action_calls_core_save_setting(self):
        with mock.patch.object(
            self.recording.recording_core, "save_setting",
            return_value={"ok": True, "message": "Saved rec_fps"},
        ) as save_setting:
            result = self.recording._run_recording_action(
                "set_setting", {"key": "rec_fps", "value": 30},
            )
        save_setting.assert_called_once_with("rec_fps", 30)
        self.assertTrue(result["ok"])

    def test_trigger_screenshot_ephemeral_invokes_capture_flag(self):
        with mock.patch.object(self.recording.subprocess, "Popen") as popen:
            result = self.recording._run_recording_action("trigger_screenshot", "ephemeral")
        self.assertTrue(result["ok"])
        popen.assert_called_once_with(
            [
                "hyprctl",
                "eval",
                'hl.dispatch(hl.dsp.exec_cmd("cloudyy-screenshot-capture --screenshot"))',
            ],
            stdout=mock.ANY, stderr=mock.ANY,
        )

    def test_trigger_screenshot_save_invokes_capture_flag(self):
        with mock.patch.object(self.recording.subprocess, "Popen") as popen:
            result = self.recording._run_recording_action("trigger_screenshot", "save")
        self.assertTrue(result["ok"])
        popen.assert_called_once_with(
            [
                "hyprctl",
                "eval",
                'hl.dispatch(hl.dsp.exec_cmd("cloudyy-screenshot-capture --screenshot-save"))',
            ],
            stdout=mock.ANY, stderr=mock.ANY,
        )

    def test_trigger_screenshot_invalid_mode_raises(self):
        with self.assertRaisesRegex(ValueError, "screenshot mode"):
            self.recording._run_recording_action("trigger_screenshot", "bogus")
        with mock.patch.object(self.recording, "_get_action_worker") as get_worker:
            with self.assertRaisesRegex(ValueError, "screenshot mode"):
                self.recording.run_recording_action({
                    "action": "trigger_screenshot", "value": "bogus", "action_id": "1",
                })
            get_worker.assert_not_called()

    def test_trigger_record_toggle_start_resolves_audio(self):
        inactive = {"active": False, "out_file": "", "selection": ""}
        with mock.patch.object(
            self.recording.recording_core, "_parse_recording_state", return_value=inactive,
        ), mock.patch.object(
            self.recording.recording_core, "load_settings", return_value={"rec_audio_mic": True},
        ), mock.patch.object(
            self.recording.recording_core, "resolve_audio_source",
            return_value={"ok": True, "source": "mic0", "message": ""},
        ) as resolve, mock.patch.object(self.recording.subprocess, "Popen") as popen:
            result = self.recording._run_recording_action("trigger_record_toggle", None)
        resolve.assert_called_once()
        self.assertTrue(result["ok"])
        popen.assert_called_once()

    def test_trigger_record_toggle_start_fails_when_audio_unresolved(self):
        inactive = {"active": False, "out_file": "", "selection": ""}
        with mock.patch.object(
            self.recording.recording_core, "_parse_recording_state", return_value=inactive,
        ), mock.patch.object(
            self.recording.recording_core, "load_settings", return_value={"rec_audio_mic": True},
        ), mock.patch.object(
            self.recording.recording_core, "resolve_audio_source",
            return_value={"ok": False, "source": None, "message": "No microphone available"},
        ), mock.patch.object(self.recording.subprocess, "Popen") as popen:
            result = self.recording._run_recording_action("trigger_record_toggle", None)
        self.assertFalse(result["ok"])
        self.assertEqual(result["message"], "No microphone available")
        popen.assert_not_called()

    def test_trigger_record_toggle_stop_skips_resolve(self):
        active = {"active": True, "out_file": "/tmp/out.mp4", "selection": ""}
        with mock.patch.object(
            self.recording.recording_core, "_parse_recording_state", return_value=active,
        ), mock.patch.object(
            self.recording.recording_core, "resolve_audio_source",
        ) as resolve, mock.patch.object(self.recording.subprocess, "Popen") as popen:
            result = self.recording._run_recording_action("trigger_record_toggle", None)
        resolve.assert_not_called()
        self.assertTrue(result["ok"])
        popen.assert_called_once_with(
            [
                "hyprctl",
                "eval",
                'hl.dispatch(hl.dsp.exec_cmd("cloudyy-screenshot-capture --record"))',
            ],
            stdout=mock.ANY, stderr=mock.ANY,
        )

    def test_file_action_dispatches_to_core_with_edit_command(self):
        with mock.patch.object(
            self.recording.recording_core, "load_settings",
            return_value={"edit_command": "gimp"},
        ), mock.patch.object(
            self.recording.recording_core, "run_file_action",
            return_value={"ok": True, "message": "Editing a.png"},
        ) as run_file_action:
            result = self.recording._run_recording_action("edit", "/tmp/a.png")
        run_file_action.assert_called_once_with("edit", "/tmp/a.png", edit_command="gimp")
        self.assertTrue(result["ok"])

    def test_ensure_thumb_action_dispatches_to_core(self):
        with mock.patch.object(
            self.recording.recording_core, "ensure_thumb",
            return_value={"ok": True, "thumb_path": "/cache/x.jpg", "message": ""},
        ) as ensure_thumb:
            result = self.recording._run_recording_action("ensure_thumb", "/tmp/a.png")
        ensure_thumb.assert_called_once_with("/tmp/a.png")
        self.assertTrue(result["ok"])

    def test_unknown_dispatch_action_raises(self):
        with self.assertRaisesRegex(ValueError, "unknown recording action"):
            self.recording._run_recording_action("explode", None)


if __name__ == "__main__":
    unittest.main()
