import unittest
from unittest import mock
from pathlib import Path
import tempfile

import lib.monitor_editor as me
from lib.ccd import monitors


def make_monitor(**overrides):
    fields = dict(
        name="DP-1", description="Test Monitor", make="Test", model="T1",
        width=2560, height=1440, refresh_rate=144.0, x=0, y=0, scale=1.0,
        transform=0, disabled=False, mirror_of="none", focused=True,
        available_modes=["2560x1440@144.00Hz"], assigned_workspaces=["1", "2"],
    )
    fields.update(overrides)
    return me.MonitorInfo(**fields)


class TestListMonitors(unittest.TestCase):
    def test_returns_monitors_as_plain_dicts_and_transforms(self):
        with mock.patch.object(me, "_fetch_monitors", return_value=([make_monitor()], [])):
            result = monitors.list_monitors({})
        self.assertEqual(len(result["monitors"]), 1)
        self.assertEqual(result["monitors"][0]["name"], "DP-1")
        self.assertEqual(result["monitors"][0]["assigned_workspaces"], ["1", "2"])
        self.assertTrue(any(t["label"] == "Normal" for t in result["transforms"]))
        self.assertTrue(any(t["label"] == "90°" for t in result["transforms"]))

    def test_merges_advanced_fields_from_persisted_monitor_rule(self):
        builder = getattr(monitors, "build_drafts", None)
        self.assertIsNotNone(builder, "build_drafts must exist")
        if builder is None:
            return
        drafts = builder(
            [make_monitor()],
            {"DP-1": (
                'hl.monitor({ output = "DP-1", mode = "2560x1440@144", '
                'position = "0x0", scale = 1, bitdepth = 10, cm = "wide", '
                'vrr = 2, icc = "/profiles/dp1.icc" })'
            )},
        )
        self.assertEqual(drafts[0]["mode"], "2560x1440@144.00Hz")
        self.assertTrue(drafts[0]["enabled"])
        self.assertEqual(drafts[0]["workspaces"], ["1", "2"])
        self.assertEqual(drafts[0]["bitdepth"], 10)
        self.assertEqual(drafts[0]["cm"], "wide")
        self.assertEqual(drafts[0]["vrr"], 2)
        self.assertEqual(drafts[0]["icc"], "/profiles/dp1.icc")

    def test_advanced_fields_have_safe_defaults_without_persisted_rule(self):
        builder = getattr(monitors, "build_drafts", None)
        self.assertIsNotNone(builder, "build_drafts must exist")
        if builder is None:
            return
        draft = builder([make_monitor()], {})[0]
        self.assertEqual(draft["bitdepth"], 8)
        self.assertEqual(draft["cm"], "srgb")
        self.assertEqual(draft["sdr_eotf"], "default")
        self.assertEqual(draft["sdrbrightness"], 1.0)
        self.assertEqual(draft["sdrsaturation"], 1.0)
        self.assertEqual(draft["vrr"], 0)
        self.assertEqual(draft["icc"], "")


class TestApplyMonitor(unittest.TestCase):
    def test_requires_name(self):
        result = monitors.apply_monitor({})
        self.assertFalse(result["ok"])

    def test_builds_line_applies_live_then_persists(self):
        with mock.patch.object(me, "_apply_monitor_line", return_value=(True, "ok")) as apply_mock, \
             mock.patch.object(me, "_write_monitor_line") as write_mock:
            result = monitors.apply_monitor({
                "name": "DP-1", "mode": "2560x1440@144.00Hz",
                "pos_x": 100, "pos_y": 0, "scale": 1.0, "transform": 0,
                "enabled": True, "mirror_of": "", "workspaces": ["1", "2"],
            })
        self.assertTrue(result["ok"])
        applied_line = apply_mock.call_args[0][0]
        self.assertIn('output = "DP-1"', applied_line)
        self.assertIn('position = "100x0"', applied_line)
        write_mock.assert_called_once_with("DP-1", applied_line, ["1", "2"])

    def test_does_not_persist_when_live_apply_fails(self):
        with mock.patch.object(me, "_apply_monitor_line", return_value=(False, "invalid mode")), \
             mock.patch.object(me, "_write_monitor_line") as write_mock:
            result = monitors.apply_monitor({"name": "DP-1", "mode": "bogus"})
        self.assertFalse(result["ok"])
        self.assertEqual(result["message"], "invalid mode")
        write_mock.assert_not_called()

    def test_disabled_monitor_builds_disable_line(self):
        with mock.patch.object(me, "_apply_monitor_line", return_value=(True, "ok")) as apply_mock, \
             mock.patch.object(me, "_write_monitor_line"):
            monitors.apply_monitor({"name": "DP-2", "enabled": False})
        self.assertIn("disable = true", apply_mock.call_args[0][0])


class TestHeadlessAndReload(unittest.TestCase):
    def test_add_headless_success(self):
        fake = mock.Mock(returncode=0, stdout="Output created", stderr="")
        with mock.patch.object(monitors.subprocess, "run", return_value=fake) as run:
            result = monitors.add_headless({})
        self.assertTrue(result["ok"])
        run.assert_called_once_with(
            ["hyprctl", "output", "create", "headless"],
            capture_output=True, text=True, timeout=5,
        )

    def test_remove_headless_requires_name(self):
        result = monitors.remove_headless({})
        self.assertFalse(result["ok"])

    def test_remove_headless_success(self):
        fake = mock.Mock(returncode=0, stdout="ok", stderr="")
        with mock.patch.object(monitors.subprocess, "run", return_value=fake) as run:
            result = monitors.remove_headless({"name": "HEADLESS-1"})
        self.assertTrue(result["ok"])
        run.assert_called_once_with(
            ["hyprctl", "output", "remove", "HEADLESS-1"],
            capture_output=True, text=True, timeout=5,
        )

    def test_reload_hyprland(self):
        fake = mock.Mock(returncode=0, stdout="", stderr="")
        with mock.patch.object(monitors.subprocess, "run", return_value=fake) as run:
            result = monitors.reload_hyprland({})
        self.assertTrue(result["ok"])
        run.assert_called_once_with(["hyprctl", "reload"], capture_output=True, text=True, check=False)

    def test_apply_layout_uses_one_lua_eval_request(self):
        apply_layout = getattr(monitors, "_apply_layout", None)
        self.assertIsNotNone(apply_layout, "_apply_layout must exist")
        if apply_layout is None:
            return
        fake = mock.Mock(returncode=0, stdout="ok", stderr="")
        drafts = [
            {"name": "DP-1", "mode": "1920x1080@60Hz", "x": 0, "y": 0,
             "scale": 1.0, "transform": 0, "enabled": True, "mirror_of": ""},
            {"name": "DP-2", "mode": "2560x1440@120Hz", "x": 1920, "y": 0,
             "scale": 1.0, "transform": 3, "enabled": True, "mirror_of": ""},
        ]
        with mock.patch.object(monitors.subprocess, "run", return_value=fake) as run:
            result = apply_layout(drafts)
        self.assertTrue(result[0])
        command = run.call_args.args[0]
        self.assertEqual(command[:2], ["hyprctl", "eval"])
        self.assertIn('output = "DP-1"', command[2])
        self.assertIn('output = "DP-2"', command[2])
        self.assertIn(";", command[2])

    def test_dpms_uses_selected_monitor(self):
        handler = getattr(monitors, "set_dpms", None)
        self.assertIsNotNone(handler, "set_dpms must exist")
        if handler is None:
            return
        fake = mock.Mock(returncode=0, stdout="ok", stderr="")
        with mock.patch.object(monitors.subprocess, "run", return_value=fake) as run:
            result = handler({"name": "DP-3", "enabled": False})
        self.assertTrue(result["ok"])
        self.assertIn('monitor = "DP-3"', run.call_args.args[0][2])
        self.assertIn('action = "off"', run.call_args.args[0][2])


class TestMonitorProtocolRegistration(unittest.TestCase):
    def test_transaction_methods_are_registered(self):
        expected = {
            "open_monitor_session",
            "test_monitor_layout",
            "keep_monitor_layout",
            "revert_monitor_layout",
            "close_monitor_session",
            "set_monitor_dpms",
        }
        self.assertTrue(expected.issubset(monitors.protocol.METHODS))


class FakeTimer:
    instances = []

    def __init__(self, interval, callback):
        self.interval = interval
        self.callback = callback
        self.started = False
        self.cancelled = False
        self.__class__.instances.append(self)

    def start(self):
        self.started = True

    def cancel(self):
        self.cancelled = True

    def fire(self):
        self.callback()


def make_session(config_path, fetch_layout, apply_layout, activate_config=lambda: (True, "ok"), events=None):
    cls = getattr(monitors, "MonitorSession", None)
    if cls is None:
        return None
    return cls(
        config_path=Path(config_path),
        fetch_layout=fetch_layout,
        apply_layout=apply_layout,
        activate_config=activate_config,
        timer_factory=FakeTimer,
        token_factory=lambda: "test-token",
        event_sender=(events if events is not None else []).append,
        clock=lambda: 100.0,
    )


class TestMonitorSessionTransactions(unittest.TestCase):
    def setUp(self):
        FakeTimer.instances.clear()
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.config = Path(self.tempdir.name) / "user_monitors.lua"
        self.original = (
            "-- exact opening config\n\n"
            'hl.monitor({ output = "DP-1", mode = "1920x1080@60", position = "0x0", scale = 1 })\n'
        )
        self.config.write_text(self.original, encoding="utf-8")
        self.opening = [{
            "name": "DP-1", "mode": "1920x1080@60Hz", "width": 1920, "height": 1080,
            "x": 0, "y": 0, "scale": 1.0, "transform": 0, "enabled": True,
            "mirror_of": "", "workspaces": [],
        }]
        self.changed = [{**self.opening[0], "x": 1920, "vrr": 2}]

    def test_open_captures_exact_config_and_live_layout(self):
        session = make_session(self.config, lambda: self.opening, lambda _layout: (True, "ok"))
        self.assertIsNotNone(session, "MonitorSession must exist")
        if session is None:
            return
        result = session.open()
        self.assertTrue(result["ok"])
        self.assertEqual(result["monitors"], self.opening)
        self.assertEqual(session.config_snapshot, self.original.encode())

    def test_apply_is_temporary_until_keep_then_persists_atomically(self):
        applied = []
        activated = []
        session = make_session(
            self.config,
            lambda: self.opening,
            lambda layout: applied.append(layout) or (True, "ok"),
            lambda: activated.append(True) or (True, "ok"),
        )
        self.assertIsNotNone(session, "MonitorSession must exist")
        if session is None:
            return
        session.open()
        tested = session.test_layout(self.changed, timeout=15)
        self.assertEqual(tested["token"], "test-token")
        self.assertEqual(tested["deadline"], 115.0)
        self.assertEqual(self.config.read_text(encoding="utf-8"), self.original)
        self.assertEqual(applied, [self.changed])
        self.assertTrue(FakeTimer.instances[-1].started)

        kept = session.keep("test-token")
        self.assertTrue(kept["ok"])
        self.assertTrue(FakeTimer.instances[-1].cancelled)
        self.assertIn('position = "1920x0"', self.config.read_text(encoding="utf-8"))
        self.assertEqual(activated, [True])

    def test_timeout_restores_live_snapshot_without_writing_config(self):
        applied = []
        events = []
        session = make_session(
            self.config,
            lambda: self.opening,
            lambda layout: applied.append(layout) or (True, "ok"),
            events=events,
        )
        self.assertIsNotNone(session, "MonitorSession must exist")
        if session is None:
            return
        session.open()
        session.test_layout(self.changed, timeout=15)
        FakeTimer.instances[-1].fire()
        self.assertEqual(applied, [self.changed, self.opening])
        self.assertEqual(self.config.read_text(encoding="utf-8"), self.original)
        self.assertEqual(events[-1]["state"], "reverted")

    def test_close_page_restores_pending_layout_and_discards_session(self):
        applied = []
        session = make_session(
            self.config,
            lambda: self.opening,
            lambda layout: applied.append(layout) or (True, "ok"),
        )
        self.assertIsNotNone(session, "MonitorSession must exist")
        if session is None:
            return
        session.open()
        session.test_layout(self.changed, timeout=15)
        result = session.close()
        self.assertTrue(result["ok"])
        self.assertEqual(applied, [self.changed, self.opening])
        self.assertIsNone(session.config_snapshot)

    def test_partial_apply_failure_immediately_attempts_rollback(self):
        applied = []

        def apply(layout):
            applied.append(layout)
            return (False, "invalid mode") if len(applied) == 1 else (True, "ok")

        session = make_session(self.config, lambda: self.opening, apply)
        self.assertIsNotNone(session, "MonitorSession must exist")
        if session is None:
            return
        session.open()
        result = session.test_layout(self.changed, timeout=15)
        self.assertFalse(result["ok"])
        self.assertEqual(result["message"], "invalid mode")
        self.assertEqual(applied, [self.changed, self.opening])
        self.assertEqual(FakeTimer.instances, [])

    def test_rejects_layout_with_no_enabled_output(self):
        applied = []
        session = make_session(
            self.config,
            lambda: self.opening,
            lambda layout: applied.append(layout) or (True, "ok"),
        )
        self.assertIsNotNone(session, "MonitorSession must exist")
        if session is None:
            return
        session.open()
        result = session.test_layout([{**self.opening[0], "enabled": False}], timeout=15)
        self.assertFalse(result["ok"])
        self.assertEqual(applied, [])


if __name__ == "__main__":
    unittest.main()
