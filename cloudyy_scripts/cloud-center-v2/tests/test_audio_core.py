import importlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


class AudioCoreTests(unittest.TestCase):
    def test_import_does_not_load_gtk(self):
        sys.modules.pop("lib.audio_core", None)
        before = set(sys.modules)
        importlib.import_module("lib.audio_core")
        loaded = set(sys.modules) - before
        self.assertFalse(any(name == "gi" or name.startswith("gi.") for name in loaded))

    def test_missing_config_enables_only_bluetooth_policy(self):
        from lib import audio_core

        with tempfile.TemporaryDirectory() as temporary:
            cfg = audio_core.load_auto_switch_config(Path(temporary) / "missing.json")
        self.assertTrue(cfg["bluetooth_auto_switch"])
        self.assertFalse(cfg["enabled"])
        self.assertEqual(cfg["output_priority"], [])

    def test_atomic_save_preserves_unknown_keys(self):
        from lib import audio_core

        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "auto_switch.json"
            path.write_text(json.dumps({"future": 7, "enabled": True}), encoding="utf-8")
            cfg = audio_core.load_auto_switch_config(path)
            cfg["bluetooth_auto_switch"] = False
            audio_core.save_auto_switch_config(cfg, path)
            saved = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(saved["future"], 7)
            self.assertFalse(saved["bluetooth_auto_switch"])
            self.assertEqual(list(path.parent.glob(".auto_switch.*")), [])

    def test_snapshot_is_json_serializable(self):
        from lib import audio_core

        sink = audio_core.Sink(1, "sink.one", "Speakers", 55, False, True, "", state="RUNNING")
        with mock.patch.object(audio_core, "list_sinks", return_value=[sink]), \
             mock.patch.object(audio_core, "list_sources", return_value=[]), \
             mock.patch.object(audio_core, "list_streams", return_value=[]), \
             mock.patch.object(audio_core, "list_cards", return_value=[]), \
             mock.patch.object(audio_core, "load_auto_switch_config", return_value=dict(audio_core.AUTO_SWITCH_DEFAULTS)):
            snapshot = audio_core.build_audio_snapshot({"active": True})
        json.dumps(snapshot)
        self.assertEqual(snapshot["sinks"][0]["name"], "sink.one")
        self.assertEqual(snapshot["sinks"][0]["type"], "Built-in")
        self.assertTrue(snapshot["service"]["active"])

    def test_unknown_action_is_rejected(self):
        from lib import audio_core

        with self.assertRaisesRegex(ValueError, "unknown audio action"):
            audio_core.execute_audio_action("shell", "target", "rm -rf")

    def test_volume_is_clamped_to_supported_range(self):
        from lib import audio_core

        with mock.patch.object(audio_core, "set_sink_volume", return_value=(True, "")) as setter:
            audio_core.execute_audio_action("set_sink_volume", "sink.one", 999)
        setter.assert_called_once_with("sink.one", 150)

    def test_list_cards_parses_pactl_json_profile_dict(self):
        from lib import audio_core

        entry = {
            "index": 49,
            "name": "alsa_card.pci-0000_01_00.1",
            "driver": "alsa",
            "active_profile": "output:hdmi-stereo",
            "profiles": {
                "off": {"description": "Off", "available": True},
                "output:hdmi-stereo": {
                    "description": "Digital Stereo (HDMI) Output",
                    "available": True,
                },
            },
        }
        with mock.patch.object(audio_core, "_pactl_json", return_value=[entry]):
            cards = audio_core.list_cards()
        self.assertEqual(len(cards), 1)
        self.assertEqual(cards[0].name, "alsa_card.pci-0000_01_00.1")
        self.assertEqual(cards[0].active_profile, "output:hdmi-stereo")
        self.assertEqual(cards[0].profiles, ["off", "output:hdmi-stereo"])
        self.assertEqual(
            cards[0].profile_descriptions["output:hdmi-stereo"],
            "Digital Stereo (HDMI) Output",
        )

    def test_list_streams_resolves_numeric_sink_index_to_name(self):
        from lib import audio_core

        sink_inputs = [{
            "index": 17770,
            "sink": 2897,
            "mute": False,
            "volume": {"front-left": {"value_percent": "74%"}},
            "properties": {
                "application.name": "Zen",
                "media.name": "YouTube",
            },
        }]
        sinks = [{
            "index": 2897,
            "name": "bluez_output.example.1",
            "description": "Headphones",
            "mute": False,
            "volume": {"front-left": {"value_percent": "40%"}},
            "properties": {},
        }]
        with mock.patch.object(audio_core, "_pactl_json", side_effect=lambda kind: {
            "sink-inputs": sink_inputs,
            "sinks": sinks,
        }.get(kind, [])), \
             mock.patch.object(audio_core, "get_default", return_value=""):
            streams = audio_core.list_streams()
        self.assertEqual(len(streams), 1)
        self.assertEqual(streams[0].sink_name, "bluez_output.example.1")

    def test_priority_labels_prefer_live_then_saved_then_bluez(self):
        from lib import audio_core

        live = [audio_core.Sink(
            1, "alsa_output.speakers", "USB Speakers", 50, False, True, "",
        )]
        with mock.patch.object(audio_core, "_bluez_device_name", return_value="Nick's Buds4 Pro") as bluez:
            labels = audio_core.resolve_output_priority_labels(
                [
                    "alsa_output.speakers",
                    "bluez_output.78_C1_1D_41_4C_91.1",
                    "bluez_output.70_8C_F2_67_D0_70.1",
                ],
                sinks=live,
                existing={
                    "bluez_output.70_8C_F2_67_D0_70.1": "HS80 Max",
                    "stale.removed": "Gone",
                },
            )
        self.assertEqual(labels["alsa_output.speakers"], "USB Speakers")
        self.assertEqual(labels["bluez_output.78_C1_1D_41_4C_91.1"], "Nick's Buds4 Pro")
        self.assertEqual(labels["bluez_output.70_8C_F2_67_D0_70.1"], "HS80 Max")
        self.assertNotIn("stale.removed", labels)
        bluez.assert_called_once_with("bluez_output.78_C1_1D_41_4C_91.1")
