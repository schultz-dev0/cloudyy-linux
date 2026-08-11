import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from lib import recording_core


class RecordingCoreSettingsTests(unittest.TestCase):
    def test_default_dirs_prefer_xdg_env(self):
        with mock.patch.dict(os.environ, {
            "XDG_PICTURES_DIR": "/pix",
            "XDG_VIDEOS_DIR": "/vids",
            "HOME": "/home/x",
        }, clear=False):
            self.assertEqual(recording_core.default_screenshots_dir(), "/pix/Screenshots")
            self.assertEqual(recording_core.default_recordings_dir(), "/vids/Captures")

    def test_default_dirs_fall_back_to_home(self):
        env = {"HOME": "/home/x"}
        for key in ("XDG_PICTURES_DIR", "XDG_VIDEOS_DIR"):
            env.setdefault(key, "")
        with mock.patch.dict(os.environ, env, clear=False):
            # Force unset
            with mock.patch.dict(os.environ, {"XDG_PICTURES_DIR": "", "XDG_VIDEOS_DIR": ""}, clear=False):
                os.environ.pop("XDG_PICTURES_DIR", None)
                os.environ.pop("XDG_VIDEOS_DIR", None)
                self.assertEqual(recording_core.default_screenshots_dir(), "/home/x/Pictures/Screenshots")
                self.assertEqual(recording_core.default_recordings_dir(), "/home/x/Videos/Captures")

    def test_expand_filename_tokens(self):
        from datetime import datetime
        now = datetime(2026, 8, 10, 15, 30, 45)
        self.assertEqual(
            recording_core.expand_filename_pattern("{datetime}_clip", now=now),
            "2026-08-10-153045_clip",
        )

    def test_silent_recording_omits_audio_passthrough(self):
        settings = {
            "rec_audio_mic": False,
            "rec_audio_desktop": False,
            "rec_fps": 60,
            "rec_codec": "",
            "rec_filetype": "mp4",
            "auto_copy": False,
            "screenshots_dir": "/pix/Screenshots",
            "recordings_dir": "/vids/Captures",
            "rec_filename_pattern": "",
        }
        args = recording_core.build_wf_recorder_passthrough(settings, audio_source=None)
        self.assertEqual(args, ["-r", "60"])


class RecordingArgsShellTests(unittest.TestCase):
    def _base_settings(self, **overrides):
        settings = {
            "rec_audio_mic": False,
            "rec_audio_desktop": False,
            "rec_fps": 60,
            "rec_codec": "",
            "rec_filetype": "mp4",
            "auto_copy": False,
            "screenshots_dir": "/pix/Screenshots",
            "recordings_dir": "/vids/Captures",
            "rec_filename_pattern": "",
        }
        settings.update(overrides)
        return settings

    def test_silent_recording_places_fps_after_double_dash_without_audio(self):
        line = recording_core.format_recording_args_shell(
            self._base_settings(), kind="rec",
        )
        self.assertNotIn("-a", line)
        self.assertIn("--", line)
        self.assertLess(line.index("--"), line.index("-r"))

    def test_audio_flag_only_after_double_dash(self):
        line = recording_core.format_recording_args_shell(
            self._base_settings(), kind="rec", audio_source="mic1",
        )
        before, after = line.split("--", 1)
        self.assertNotIn("-a", before)
        self.assertIn("-amic1", after)

    def test_shot_kind_never_includes_wf_passthrough_or_audio(self):
        line = recording_core.format_recording_args_shell(
            self._base_settings(), kind="shot", audio_source="mic1",
        )
        self.assertNotIn("--", line)
        self.assertNotIn("-a", line)


class RecordingArgsCliTests(unittest.TestCase):
    def test_should_resolve_audio_only_when_requested_or_both_boxes(self):
        from lib import recording_args

        silent = {"rec_audio_mic": False, "rec_audio_desktop": False}
        mic_only = {"rec_audio_mic": True, "rec_audio_desktop": False}
        both = {"rec_audio_mic": True, "rec_audio_desktop": True}

        self.assertFalse(recording_args.should_resolve_audio(silent, kind="rec", ensure_audio=False))
        self.assertFalse(recording_args.should_resolve_audio(mic_only, kind="rec", ensure_audio=False))
        self.assertTrue(recording_args.should_resolve_audio(both, kind="rec", ensure_audio=False))
        self.assertTrue(recording_args.should_resolve_audio(mic_only, kind="rec", ensure_audio=True))
        self.assertFalse(recording_args.should_resolve_audio(silent, kind="rec", ensure_audio=True))
        self.assertFalse(recording_args.should_resolve_audio(both, kind="shot", ensure_audio=True))

    def test_print_recording_args_exits_on_ensure_audio_failure(self):
        from lib import recording_args

        settings = {
            "rec_audio_mic": True,
            "rec_audio_desktop": True,
            "rec_mic_device": "",
            "rec_desktop_device": "",
            "rec_fps": 60,
            "rec_codec": "",
            "rec_filetype": "mp4",
            "auto_copy": False,
            "screenshots_dir": "/pix/Screenshots",
            "recordings_dir": "/vids/Captures",
        }
        with mock.patch.object(
            recording_core, "resolve_audio_source",
            return_value={"ok": False, "source": None, "message": "pactl failed"},
        ):
            with self.assertRaises(SystemExit) as ctx:
                recording_args.print_recording_args(
                    kind="rec", ensure_audio=True, settings=settings,
                )
            self.assertIn("pactl failed", str(ctx.exception))


class RecordingAudioResolveTests(unittest.TestCase):
    def test_neither_box_returns_no_source(self):
        result = recording_core.resolve_audio_source({
            "rec_audio_mic": False,
            "rec_audio_desktop": False,
            "rec_mic_device": "",
            "rec_desktop_device": "",
        })
        self.assertTrue(result["ok"])
        self.assertIsNone(result["source"])

    def test_mic_only_uses_named_or_default(self):
        with mock.patch.object(recording_core, "list_audio_inputs", return_value={
            "mics": [{"name": "mic1", "description": "Mic", "is_default": True}],
            "desktops": [{"name": "sink.monitor", "description": "Speakers", "is_default": True}],
        }):
            result = recording_core.resolve_audio_source({
                "rec_audio_mic": True,
                "rec_audio_desktop": False,
                "rec_mic_device": "",
                "rec_desktop_device": "",
            })
            self.assertTrue(result["ok"])
            self.assertEqual(result["source"], "mic1")

    def test_desktop_only_uses_named_or_default(self):
        with mock.patch.object(recording_core, "list_audio_inputs", return_value={
            "mics": [{"name": "mic1", "description": "Mic", "is_default": True}],
            "desktops": [{"name": "sink.monitor", "description": "Speakers", "is_default": True}],
        }):
            result = recording_core.resolve_audio_source({
                "rec_audio_mic": False,
                "rec_audio_desktop": True,
                "rec_mic_device": "",
                "rec_desktop_device": "",
            })
            self.assertTrue(result["ok"])
            self.assertEqual(result["source"], "sink.monitor")

    def test_both_calls_ensure_combine(self):
        with mock.patch.object(recording_core, "list_audio_inputs", return_value={
            "mics": [{"name": "mic1", "description": "Mic", "is_default": True}],
            "desktops": [{"name": "sink.monitor", "description": "Speakers", "is_default": True}],
        }), mock.patch.object(
            recording_core, "ensure_combine_source",
            return_value={"ok": True, "source": "cloudyy_recording_mix.monitor", "message": ""},
        ) as ensure:
            result = recording_core.resolve_audio_source({
                "rec_audio_mic": True,
                "rec_audio_desktop": True,
                "rec_mic_device": "mic1",
                "rec_desktop_device": "sink.monitor",
            })
            ensure.assert_called_once_with("mic1", "sink.monitor")
            self.assertEqual(result["source"], "cloudyy_recording_mix.monitor")

    def test_both_combine_failure_does_not_fallback(self):
        with mock.patch.object(recording_core, "list_audio_inputs", return_value={
            "mics": [{"name": "mic1", "description": "Mic", "is_default": True}],
            "desktops": [{"name": "sink.monitor", "description": "Speakers", "is_default": True}],
        }), mock.patch.object(
            recording_core, "ensure_combine_source",
            return_value={"ok": False, "source": "", "message": "pactl failed"},
        ):
            result = recording_core.resolve_audio_source({
                "rec_audio_mic": True,
                "rec_audio_desktop": True,
                "rec_mic_device": "",
                "rec_desktop_device": "",
            })
            self.assertFalse(result["ok"])
            self.assertIsNone(result.get("source") or None)


class RecordingAudioInputsTests(unittest.TestCase):
    def test_list_audio_inputs_reuses_audio_core(self):
        from lib import audio_core

        fake_source = audio_core.Source(
            index=0, name="mic1", description="Mic", volume=100, muted=False,
            is_default=True, active_port="",
        )
        fake_sink = audio_core.Sink(
            index=0, name="alsa_output.speakers", description="Speakers", volume=100,
            muted=False, is_default=True, active_port="",
        )
        with mock.patch.object(audio_core, "list_sources", return_value=[fake_source]), \
                mock.patch.object(audio_core, "list_sinks", return_value=[fake_sink]):
            result = recording_core.list_audio_inputs()
        self.assertEqual(result["mics"], [{"name": "mic1", "description": "Mic", "is_default": True}])
        self.assertEqual(
            result["desktops"],
            [{"name": "alsa_output.speakers.monitor", "description": "Speakers", "is_default": True}],
        )


class RecordingCombineTests(unittest.TestCase):
    def test_ensure_combine_creates_sink_and_relinks_loopbacks(self):
        calls: list[list[str]] = []

        def fake_run(args, timeout=8):
            calls.append(args)
            if args[:3] == ["list", "sinks", "short"]:
                return True, "0\tother_sink\tmodule.x\ts16le 2ch 48000Hz\tIDLE\n"
            if args[:2] == ["load-module", "module-null-sink"]:
                return True, "123"
            if args[:3] == ["list", "modules", "short"]:
                return True, "5\tmodule-loopback\tsink=cloudyy_recording_mix source=old_mic\n"
            if args[0] == "unload-module":
                return True, ""
            if args[:2] == ["load-module", "module-loopback"]:
                return True, "10"
            return False, "unexpected call"

        with mock.patch.object(recording_core, "_pactl_run", side_effect=fake_run):
            result = recording_core.ensure_combine_source("mic1", "sink.monitor")

        self.assertTrue(result["ok"])
        self.assertEqual(result["source"], "cloudyy_recording_mix.monitor")
        self.assertIn(["unload-module", "5"], calls)
        self.assertIn(
            ["load-module", "module-loopback", "source=mic1", "sink=cloudyy_recording_mix"], calls,
        )
        self.assertIn(
            ["load-module", "module-loopback", "source=sink.monitor", "sink=cloudyy_recording_mix"], calls,
        )

    def test_ensure_combine_skips_create_when_sink_already_exists(self):
        def fake_run(args, timeout=8):
            if args[:3] == ["list", "sinks", "short"]:
                return True, "0\tcloudyy_recording_mix\tmodule.x\ts16le 2ch 48000Hz\tIDLE\n"
            if args[:3] == ["list", "modules", "short"]:
                return True, ""
            if args[:2] == ["load-module", "module-loopback"]:
                return True, "10"
            return False, "unexpected call"

        with mock.patch.object(recording_core, "_pactl_run", side_effect=fake_run) as runner:
            result = recording_core.ensure_combine_source("mic1", "sink.monitor")

        self.assertTrue(result["ok"])
        for call in runner.call_args_list:
            self.assertNotEqual(list(call.args[0])[:2], ["load-module", "module-null-sink"])

    def test_ensure_combine_null_sink_failure_returns_not_ok(self):
        def fake_run(args, timeout=8):
            if args[:3] == ["list", "sinks", "short"]:
                return True, ""
            if args[:2] == ["load-module", "module-null-sink"]:
                return False, "pactl: command failed"
            return False, "unexpected call"

        with mock.patch.object(recording_core, "_pactl_run", side_effect=fake_run):
            result = recording_core.ensure_combine_source("mic1", "sink.monitor")

        self.assertFalse(result["ok"])
        self.assertIn("pactl", result["message"])

    def test_ensure_combine_loopback_failure_returns_not_ok(self):
        def fake_run(args, timeout=8):
            if args[:3] == ["list", "sinks", "short"]:
                return True, "0\tcloudyy_recording_mix\tmodule.x\ts16le 2ch 48000Hz\tIDLE\n"
            if args[:3] == ["list", "modules", "short"]:
                return True, ""
            if args[:2] == ["load-module", "module-loopback"]:
                return False, "no such source"
            return False, "unexpected call"

        with mock.patch.object(recording_core, "_pactl_run", side_effect=fake_run):
            result = recording_core.ensure_combine_source("mic1", "sink.monitor")

        self.assertFalse(result["ok"])
        self.assertIn("no such source", result["message"])

    def test_loopback_ids_do_not_match_backup_sink_substring(self):
        def fake_run(args, timeout=8):
            if args[:3] == ["list", "modules", "short"]:
                return True, (
                    "5\tmodule-loopback\tsink=cloudyy_recording_mix_backup source=old_mic\n"
                    "6\tmodule-loopback\tsink=cloudyy_recording_mix source=old_desktop\n"
                )
            return False, "unexpected call"

        with mock.patch.object(recording_core, "_pactl_run", side_effect=fake_run):
            ok, ids = recording_core._loopback_module_ids_for_sink("cloudyy_recording_mix")

        self.assertTrue(ok)
        self.assertEqual(ids, ["6"])

    def test_ensure_combine_requires_both_sources(self):
        result = recording_core.ensure_combine_source("", "sink.monitor")
        self.assertFalse(result["ok"])

    def test_ensure_combine_module_list_failure_returns_not_ok(self):
        def fake_run(args, timeout=8):
            if args[:3] == ["list", "sinks", "short"]:
                return True, "0\tcloudyy_recording_mix\tmodule.x\ts16le 2ch 48000Hz\tIDLE\n"
            if args[:3] == ["list", "modules", "short"]:
                return False, "pactl: connection refused"
            return False, "unexpected call"

        with mock.patch.object(recording_core, "_pactl_run", side_effect=fake_run) as runner:
            result = recording_core.ensure_combine_source("mic1", "sink.monitor")

        self.assertFalse(result["ok"])
        for call in runner.call_args_list:
            self.assertNotEqual(list(call.args[0])[:2], ["load-module", "module-loopback"])

    def test_ensure_combine_does_not_unload_backup_sink_loopback(self):
        calls: list[list[str]] = []

        def fake_run(args, timeout=8):
            calls.append(args)
            if args[:3] == ["list", "sinks", "short"]:
                return True, "0\tcloudyy_recording_mix\tmodule.x\ts16le 2ch 48000Hz\tIDLE\n"
            if args[:3] == ["list", "modules", "short"]:
                return True, "5\tmodule-loopback\tsink=cloudyy_recording_mix_backup source=old_mic\n"
            if args[:2] == ["load-module", "module-loopback"]:
                return True, "10"
            return False, "unexpected call"

        with mock.patch.object(recording_core, "_pactl_run", side_effect=fake_run):
            result = recording_core.ensure_combine_source("mic1", "sink.monitor")

        self.assertTrue(result["ok"])
        self.assertNotIn(["unload-module", "5"], calls)

    def test_ensure_combine_unload_failure_returns_not_ok_and_stops_before_relinking(self):
        def fake_run(args, timeout=8):
            if args[:3] == ["list", "sinks", "short"]:
                return True, "0\tcloudyy_recording_mix\tmodule.x\ts16le 2ch 48000Hz\tIDLE\n"
            if args[:3] == ["list", "modules", "short"]:
                return True, "5\tmodule-loopback\tsink=cloudyy_recording_mix source=old_mic\n"
            if args[0] == "unload-module":
                return False, "pactl: no such module"
            if args[:2] == ["load-module", "module-loopback"]:
                return True, "10"
            return False, "unexpected call"

        with mock.patch.object(recording_core, "_pactl_run", side_effect=fake_run) as runner:
            result = recording_core.ensure_combine_source("mic1", "sink.monitor")

        self.assertFalse(result["ok"])
        self.assertIn("no such module", result["message"])
        for call in runner.call_args_list:
            self.assertNotEqual(list(call.args[0])[:2], ["load-module", "module-loopback"])


class RecordingGalleryTests(unittest.TestCase):
    def test_list_gallery_newest_first(self):
        with tempfile.TemporaryDirectory() as tmp:
            shots = Path(tmp) / "shots"
            vids = Path(tmp) / "vids"
            shots.mkdir(); vids.mkdir()
            a = shots / "a.png"; a.write_bytes(b"x")
            b = vids / "b.mp4"; b.write_bytes(b"y" * 10)
            os.utime(a, (1000, 1000))
            os.utime(b, (2000, 2000))
            items = recording_core.list_gallery({
                "screenshots_dir": str(shots),
                "recordings_dir": str(vids),
            })
            self.assertEqual([i["path"] for i in items], [str(b), str(a)])
            self.assertEqual(items[0]["kind"], "recording")
            self.assertEqual(items[1]["kind"], "screenshot")

    def test_list_gallery_ignores_unknown_extensions_and_missing_dirs(self):
        with tempfile.TemporaryDirectory() as tmp:
            shots = Path(tmp) / "shots"
            shots.mkdir()
            (shots / "notes.txt").write_text("hi")
            (shots / "a.png").write_bytes(b"x")
            items = recording_core.list_gallery({
                "screenshots_dir": str(shots),
                "recordings_dir": str(Path(tmp) / "missing"),
            })
            self.assertEqual(len(items), 1)
            self.assertTrue(items[0]["path"].endswith("a.png"))

    def test_list_gallery_reports_empty_thumb_path_until_generated(self):
        with tempfile.TemporaryDirectory() as tmp:
            shots = Path(tmp) / "shots"
            shots.mkdir()
            (shots / "a.png").write_bytes(b"x")
            items = recording_core.list_gallery({
                "screenshots_dir": str(shots),
                "recordings_dir": "",
            })
            self.assertEqual(items[0]["thumb_path"], "")

    def test_list_gallery_dedupes_when_dirs_are_the_same(self):
        with tempfile.TemporaryDirectory() as tmp:
            shared = Path(tmp) / "shared"
            shared.mkdir()
            (shared / "a.png").write_bytes(b"x")
            (shared / "b.mp4").write_bytes(b"y")
            items = recording_core.list_gallery({
                "screenshots_dir": str(shared),
                "recordings_dir": str(shared),
            })
            self.assertEqual(len(items), 2)

            items_via_relative = recording_core.list_gallery({
                "screenshots_dir": str(shared),
                "recordings_dir": str(shared) + os.sep,
            })
            self.assertEqual(len(items_via_relative), 2)


class RecordingThumbTests(unittest.TestCase):
    def test_thumb_path_for_is_stable_for_same_path_and_mtime(self):
        first = recording_core.thumb_path_for("/a/b.mp4", 1000)
        second = recording_core.thumb_path_for("/a/b.mp4", 1000)
        self.assertEqual(first, second)
        self.assertEqual(first.suffix, ".jpg")

    def test_thumb_path_for_differs_on_mtime_change(self):
        first = recording_core.thumb_path_for("/a/b.mp4", 1000)
        second = recording_core.thumb_path_for("/a/b.mp4", 2000)
        self.assertNotEqual(first, second)

    def test_ensure_thumb_copies_image_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache_dir = Path(tmp) / "cache"
            src = Path(tmp) / "a.png"
            src.write_bytes(b"fake-png-bytes")
            with mock.patch.object(recording_core, "THUMB_CACHE_DIR", cache_dir):
                result = recording_core.ensure_thumb(str(src))
            self.assertTrue(result["ok"])
            self.assertTrue(Path(result["thumb_path"]).exists())

    def test_ensure_thumb_uses_ffmpeg_for_video(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache_dir = Path(tmp) / "cache"
            src = Path(tmp) / "b.mp4"
            src.write_bytes(b"fake-mp4-bytes")

            def fake_ffmpeg_run(argv, capture_output=True, text=True, timeout=20):
                Path(argv[-1]).write_bytes(b"jpeg-bytes")
                return mock.Mock(returncode=0, stderr="")

            with mock.patch.object(recording_core, "THUMB_CACHE_DIR", cache_dir), \
                    mock.patch.object(recording_core.shutil, "which", return_value="/usr/bin/ffmpeg"), \
                    mock.patch.object(recording_core.subprocess, "run", side_effect=fake_ffmpeg_run):
                result = recording_core.ensure_thumb(str(src))
            self.assertTrue(result["ok"])
            self.assertTrue(Path(result["thumb_path"]).exists())

    def test_ensure_thumb_deletes_partial_output_on_ffmpeg_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache_dir = Path(tmp) / "cache"
            src = Path(tmp) / "b.mp4"
            src.write_bytes(b"fake-mp4-bytes")

            def fake_ffmpeg_run(argv, capture_output=True, text=True, timeout=20):
                Path(argv[-1]).write_bytes(b"partial-jpeg-bytes")
                return mock.Mock(returncode=1, stderr="ffmpeg exploded")

            with mock.patch.object(recording_core, "THUMB_CACHE_DIR", cache_dir), \
                    mock.patch.object(recording_core.shutil, "which", return_value="/usr/bin/ffmpeg"), \
                    mock.patch.object(recording_core.subprocess, "run", side_effect=fake_ffmpeg_run):
                result = recording_core.ensure_thumb(str(src))
            self.assertFalse(result["ok"])
            expected_thumb = recording_core.thumb_path_for(str(src), int(src.stat().st_mtime * 1000))
            self.assertFalse(expected_thumb.exists())

    def test_ensure_thumb_deletes_partial_output_on_ffmpeg_exception(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache_dir = Path(tmp) / "cache"
            src = Path(tmp) / "b.mp4"
            src.write_bytes(b"fake-mp4-bytes")

            def fake_ffmpeg_run(argv, capture_output=True, text=True, timeout=20):
                Path(argv[-1]).write_bytes(b"partial-jpeg-bytes")
                raise TimeoutError("ffmpeg timed out")

            with mock.patch.object(recording_core, "THUMB_CACHE_DIR", cache_dir), \
                    mock.patch.object(recording_core.shutil, "which", return_value="/usr/bin/ffmpeg"), \
                    mock.patch.object(recording_core.subprocess, "run", side_effect=fake_ffmpeg_run):
                result = recording_core.ensure_thumb(str(src))
            self.assertFalse(result["ok"])
            expected_thumb = recording_core.thumb_path_for(str(src), int(src.stat().st_mtime * 1000))
            self.assertFalse(expected_thumb.exists())

    def test_ensure_thumb_missing_ffmpeg_fails_for_video(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache_dir = Path(tmp) / "cache"
            src = Path(tmp) / "b.mp4"
            src.write_bytes(b"fake-mp4-bytes")
            with mock.patch.object(recording_core, "THUMB_CACHE_DIR", cache_dir), \
                    mock.patch.object(recording_core.shutil, "which", return_value=None):
                result = recording_core.ensure_thumb(str(src))
            self.assertFalse(result["ok"])

    def test_ensure_thumb_returns_cached_without_regenerating(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache_dir = Path(tmp) / "cache"
            src = Path(tmp) / "a.png"
            src.write_bytes(b"fake-png-bytes")
            with mock.patch.object(recording_core, "THUMB_CACHE_DIR", cache_dir):
                first = recording_core.ensure_thumb(str(src))
                with mock.patch("shutil.copyfile") as copyfile:
                    second = recording_core.ensure_thumb(str(src))
                copyfile.assert_not_called()
            self.assertEqual(first["thumb_path"], second["thumb_path"])

    def test_ensure_thumb_missing_source_file_fails(self):
        result = recording_core.ensure_thumb("/no/such/file.png")
        self.assertFalse(result["ok"])


class RecordingFileActionTests(unittest.TestCase):
    def test_open_action_prefers_gio_open(self):
        with mock.patch.object(recording_core.shutil, "which", side_effect=lambda c: "/usr/bin/gio" if c == "gio" else None), \
             mock.patch.object(recording_core.subprocess, "Popen") as popen:
            result = recording_core.run_file_action("open", "/tmp/a.png", edit_command="xdg-open")
        self.assertTrue(result["ok"])
        popen.assert_called_once_with(
            ["gio", "open", "/tmp/a.png"], stdout=mock.ANY, stderr=mock.ANY,
        )

    def test_open_action_falls_back_to_xdg_open_without_gio(self):
        with mock.patch.object(recording_core.shutil, "which", return_value=None), \
             mock.patch.object(recording_core.subprocess, "Popen") as popen:
            recording_core.run_file_action("open", "/tmp/a.png", edit_command="xdg-open")
        popen.assert_called_once_with(
            ["xdg-open", "/tmp/a.png"], stdout=mock.ANY, stderr=mock.ANY,
        )

    def test_edit_action_uses_configured_edit_command(self):
        with mock.patch.object(recording_core.subprocess, "Popen") as popen:
            result = recording_core.run_file_action("edit", "/tmp/a.png", edit_command="gimp")
        self.assertTrue(result["ok"])
        popen.assert_called_once_with(
            ["gimp", "/tmp/a.png"], stdout=mock.ANY, stderr=mock.ANY,
        )

    def test_edit_action_maps_xdg_open_to_gio_open(self):
        with mock.patch.object(recording_core.shutil, "which", side_effect=lambda c: "/usr/bin/gio" if c == "gio" else None), \
             mock.patch.object(recording_core.subprocess, "Popen") as popen:
            recording_core.run_file_action("edit", "/tmp/a.png", edit_command="")
        popen.assert_called_once_with(
            ["gio", "open", "/tmp/a.png"], stdout=mock.ANY, stderr=mock.ANY,
        )

    def test_reveal_action_uses_file_manager_env(self):
        with mock.patch.dict(recording_core.os.environ, {"FILE_MANAGER": "thunar"}, clear=False), \
             mock.patch.object(recording_core.subprocess, "Popen") as popen:
            recording_core.run_file_action("reveal", "/tmp/dir/a.png", edit_command="xdg-open")
        popen.assert_called_once_with(
            ["thunar", "/tmp/dir"], stdout=mock.ANY, stderr=mock.ANY,
        )

    def test_reveal_action_prefers_nautilus_select(self):
        with mock.patch.dict(recording_core.os.environ, {"FILE_MANAGER": ""}, clear=False), \
             mock.patch.object(
                 recording_core.shutil, "which",
                 side_effect=lambda c: "/usr/bin/nautilus" if c == "nautilus" else "/usr/bin/gio" if c == "gio" else None,
             ), \
             mock.patch.object(recording_core.subprocess, "Popen") as popen:
            recording_core.run_file_action("reveal", "/tmp/dir/a.png", edit_command="xdg-open")
        popen.assert_called_once_with(
            ["nautilus", "--select", "/tmp/dir/a.png"], stdout=mock.ANY, stderr=mock.ANY,
        )

    def test_copy_action_screenshot_pipes_image_bytes_to_wl_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.png"
            path.write_bytes(b"x")
            with mock.patch.object(recording_core.shutil, "which", return_value="/usr/bin/wl-copy"), \
                    mock.patch.object(recording_core.subprocess, "run", return_value=mock.Mock(returncode=0)) as run:
                result = recording_core.run_file_action("copy", str(path), edit_command="xdg-open")
            self.assertTrue(result["ok"])
            args, kwargs = run.call_args
            self.assertEqual(args[0][0], "wl-copy")
            self.assertIn("image/png", args[0])

    def test_copy_action_recording_copies_uri_list(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "b.mp4"
            path.write_bytes(b"y")
            with mock.patch.object(recording_core.shutil, "which", return_value="/usr/bin/wl-copy"), \
                    mock.patch.object(recording_core.subprocess, "run", return_value=mock.Mock(returncode=0)) as run:
                result = recording_core.run_file_action("copy", str(path), edit_command="xdg-open")
            self.assertTrue(result["ok"])
            args, kwargs = run.call_args
            self.assertIn("text/uri-list", args[0])
            expected_uri = path.resolve().as_uri()
            self.assertEqual(kwargs.get("input", ""), f"{expected_uri}\r\n")

    def test_copy_action_wl_copy_timeout_fails_gracefully(self):
        import subprocess as subprocess_module

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.png"
            path.write_bytes(b"x")
            with mock.patch.object(recording_core.shutil, "which", return_value="/usr/bin/wl-copy"), \
                    mock.patch.object(
                        recording_core.subprocess, "run",
                        side_effect=subprocess_module.TimeoutExpired(cmd="wl-copy", timeout=10),
                    ):
                result = recording_core.run_file_action("copy", str(path), edit_command="xdg-open")
            self.assertFalse(result["ok"])
            self.assertIn("message", result)

    def test_copy_action_missing_wl_copy_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.png"
            path.write_bytes(b"x")
            with mock.patch.object(recording_core.shutil, "which", return_value=None):
                result = recording_core.run_file_action("copy", str(path), edit_command="xdg-open")
            self.assertFalse(result["ok"])

    def test_delete_action_unlinks_file_and_thumb(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache_dir = Path(tmp) / "cache"
            path = Path(tmp) / "a.png"
            path.write_bytes(b"x")
            with mock.patch.object(recording_core, "THUMB_CACHE_DIR", cache_dir):
                thumb = recording_core.ensure_thumb(str(path))
                self.assertTrue(Path(thumb["thumb_path"]).exists())
                result = recording_core.run_file_action("delete", str(path), edit_command="xdg-open")
                self.assertTrue(result["ok"])
                self.assertFalse(path.exists())
                self.assertFalse(Path(thumb["thumb_path"]).exists())

    def test_delete_action_swallows_thumb_unlink_errors(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache_dir = Path(tmp) / "cache"
            path = Path(tmp) / "a.png"
            path.write_bytes(b"x")
            with mock.patch.object(recording_core, "THUMB_CACHE_DIR", cache_dir):
                recording_core.ensure_thumb(str(path))
                with mock.patch.object(Path, "unlink") as unlink:
                    unlink.side_effect = [None, PermissionError("nope")]
                    result = recording_core.run_file_action("delete", str(path), edit_command="xdg-open")
            self.assertTrue(result["ok"])

    def test_delete_action_missing_file_fails(self):
        result = recording_core.run_file_action("delete", "/no/such/file.png", edit_command="xdg-open")
        self.assertFalse(result["ok"])

    def test_unknown_action_raises(self):
        with self.assertRaisesRegex(ValueError, "unknown recording file action"):
            recording_core.run_file_action("shell", "/tmp/a.png", edit_command="xdg-open")


class RecordingSnapshotTests(unittest.TestCase):
    def test_snapshot_is_json_serializable_and_has_expected_keys(self):
        with mock.patch.object(recording_core, "list_audio_inputs", return_value={"mics": [], "desktops": []}), \
                mock.patch.object(recording_core, "list_gallery", return_value=[]):
            snapshot = recording_core.build_recording_snapshot()
        json.dumps(snapshot)
        self.assertIn("settings", snapshot)
        self.assertIn("audio_inputs", snapshot)
        self.assertIn("recording", snapshot)
        self.assertIn("gallery", snapshot)
        self.assertFalse(snapshot["recording"]["active"])
        self.assertEqual(snapshot["revision"], 0)
        self.assertIsInstance(snapshot["revision"], int)
        self.assertFalse(snapshot["stale"])
        self.assertEqual(snapshot["error"], "")

    def test_snapshot_reads_active_recording_state_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            state_file = Path(tmp) / "cloudyy-recording.state"
            state_file.write_text("RECORDING=1\nOUT_FILE=/vids/clip.mp4\nSELECTION=region\n")
            with mock.patch.object(recording_core, "RECORDING_STATE_FILE", state_file), \
                    mock.patch.object(recording_core, "list_audio_inputs", return_value={"mics": [], "desktops": []}), \
                    mock.patch.object(recording_core, "list_gallery", return_value=[]):
                snapshot = recording_core.build_recording_snapshot()
        self.assertTrue(snapshot["recording"]["active"])
        self.assertEqual(snapshot["recording"]["out_file"], "/vids/clip.mp4")
        self.assertEqual(snapshot["recording"]["selection"], "region")

    def test_allowed_actions_contains_expected_names(self):
        expected = {
            "set_setting", "trigger_screenshot", "trigger_record_toggle",
            "open", "edit", "copy", "delete", "reveal", "ensure_thumb",
        }
        self.assertEqual(recording_core.ALLOWED_ACTIONS, frozenset(expected))
