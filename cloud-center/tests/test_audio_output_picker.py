from __future__ import annotations

import unittest
from unittest import mock

from lib import audio_core, audio_output_picker


class AudioOutputPickerTests(unittest.TestCase):
    def setUp(self):
        self.sink = audio_core.Sink(1, "sink.usb", "USB Speakers", 55, False, True, "",
                                    properties={"device.bus": "usb"})

    def test_lists_friendly_names_and_current_output_without_full_snapshot(self):
        with mock.patch.object(audio_core, "list_sinks", return_value=[self.sink]), \
             mock.patch.object(audio_core, "build_audio_snapshot", side_effect=AssertionError("no full backend")):
            result = audio_output_picker.run(["list"])
        self.assertTrue(result["ok"])
        self.assertEqual(result["outputs"][0]["description"], "USB Speakers")
        self.assertTrue(result["outputs"][0]["is_default"])
        self.assertEqual(result["outputs"][0]["type"], "USB")

    def test_switch_sets_default_and_moves_existing_playback_streams(self):
        streams = [audio_core.Stream(10, "Player", "Music", "old", 50, False),
                   audio_core.Stream(11, "Browser", "Video", "old", 50, False)]
        with mock.patch.object(audio_core, "list_sinks", return_value=[self.sink]), \
             mock.patch.object(audio_core, "list_streams", return_value=streams), \
             mock.patch.object(audio_core, "_run_cmd", return_value=(True, "")) as command:
            result = audio_output_picker.run(["switch", self.sink.name])
        self.assertTrue(result["ok"])
        self.assertEqual(command.call_args_list, [
            mock.call(["pactl", "set-default-sink", "sink.usb"]),
            mock.call(["pactl", "move-sink-input", "10", "sink.usb"]),
            mock.call(["pactl", "move-sink-input", "11", "sink.usb"]),
        ])

    def test_disconnected_output_does_not_change_default(self):
        with mock.patch.object(audio_core, "list_sinks", return_value=[]), \
             mock.patch.object(audio_core, "switch_output") as switch:
            result = audio_output_picker.run(["switch", "gone"])
        self.assertFalse(result["ok"])
        switch.assert_not_called()

    def test_failed_switch_is_reported_and_does_not_move_streams(self):
        with mock.patch.object(audio_core, "list_sinks", return_value=[self.sink]), \
             mock.patch.object(audio_core, "set_default_sink", return_value=(False, "Device unavailable")), \
             mock.patch.object(audio_core, "migrate_all_streams_to_sink") as move:
            result = audio_output_picker.run(["switch", self.sink.name])
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "Device unavailable")
        move.assert_not_called()
