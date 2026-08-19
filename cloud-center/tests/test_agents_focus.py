from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from lib.agents import focus as focus_module
from lib.agents.focus import focus_session


BOOT_TIME = 1_700_000_000
STARTED_AT = "2023-11-14T22:13:22.500000+00:00"


def _write_process(
    proc_root: Path,
    pid: int,
    parent: int,
    start_ticks: int,
    agent_id: str = "claude",
) -> Path:
    pid_dir = proc_root / str(pid)
    pid_dir.mkdir()
    (pid_dir / "exe").symlink_to(f"/usr/bin/{agent_id}")
    (pid_dir / "comm").write_text(f"{agent_id}\n", encoding="utf-8")
    (pid_dir / "cmdline").write_bytes(f"/usr/bin/{agent_id}\0".encode())
    fields_before_start = " ".join(["0"] * 17)
    (pid_dir / "stat").write_text(
        f"{pid} (agent process) S {parent} {fields_before_start} {start_ticks} 0 0\n",
        encoding="utf-8",
    )
    return pid_dir


_NO_TMUX = SimpleNamespace(returncode=1, stdout="", stderr="no tmux server running")


class _Runner:
    def __init__(
        self,
        clients: list[dict],
        dispatch_returncode: int = 0,
        panes: str = "",
        tmux_clients: str = "",
    ):
        self.clients = clients
        self.dispatch_returncode = dispatch_returncode
        self.calls = []
        self.after_clients = None
        self.panes = panes
        self.tmux_clients = tmux_clients

    def __call__(self, argv, **kwargs):
        self.calls.append((argv, kwargs))
        if argv[:2] == ["tmux", "list-panes"]:
            if not self.panes:
                return _NO_TMUX
            return SimpleNamespace(returncode=0, stdout=self.panes, stderr="")
        if argv[:2] == ["tmux", "list-clients"]:
            if not self.tmux_clients:
                return _NO_TMUX
            return SimpleNamespace(returncode=0, stdout=self.tmux_clients, stderr="")
        if argv == ["hyprctl", "clients", "-j"]:
            result = SimpleNamespace(
                returncode=0,
                stdout=json.dumps(self.clients),
                stderr="",
            )
            if self.after_clients is not None:
                self.after_clients()
            return result
        return SimpleNamespace(
            returncode=self.dispatch_returncode,
            stdout="",
            stderr="dispatch failed" if self.dispatch_returncode else "",
        )


class AgentsFocusTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.proc_root = Path(self.tmp.name) / "proc"
        self.proc_root.mkdir()
        (self.proc_root / "stat").write_text(
            f"cpu 1 2 3 4\nbtime {BOOT_TIME}\n",
            encoding="utf-8",
        )
        self.clock_ticks = mock.patch("lib.agents.focus.os.sysconf", return_value=100)
        self.clock_ticks.start()
        self.addCleanup(self.clock_ticks.stop)
        self.proc_patch = mock.patch("lib.agents.focus._PROC_ROOT", self.proc_root)
        self.proc_patch.start()
        self.addCleanup(self.proc_patch.stop)

    def test_focuses_direct_pid_with_exact_dispatch_argv(self):
        _write_process(self.proc_root, 100, 1, 250)
        runner = _Runner([{"pid": 100, "address": "0x1234abcd"}])

        result = focus_session("claude", 100, STARTED_AT, runner)

        self.assertEqual(result, 0)
        self.assertEqual(
            [call[0] for call in runner.calls],
            [
                ["tmux", "list-panes", "-a", "-F", "#{pane_pid} #{session_name}"],
                ["hyprctl", "clients", "-j"],
                [
                    "hyprctl", "dispatch",
                    'hl.dsp.focus({window = "address:0x1234abcd"})',
                ],
            ],
        )

    def test_focuses_nearest_correlated_terminal_ancestor(self):
        _write_process(self.proc_root, 200, 150, 250)
        _write_process(self.proc_root, 150, 125, 100)
        _write_process(self.proc_root, 125, 1, 50)
        runner = _Runner([
            {"pid": 125, "address": "0xgrandparent"},
            {"pid": 150, "address": "0xparent"},
        ])

        result = focus_session("claude", 200, STARTED_AT, runner)

        self.assertEqual(result, 0)
        self.assertEqual(
            runner.calls[-1][0],
            [
                "hyprctl", "dispatch",
                'hl.dsp.focus({window = "address:0xparent"})',
            ],
        )

    def test_returns_no_correlation_without_dispatch(self):
        _write_process(self.proc_root, 300, 250, 250)
        _write_process(self.proc_root, 250, 1, 100)
        runner = _Runner([{"pid": 999, "address": "0xother"}])

        self.assertEqual(focus_session("claude", 300, STARTED_AT, runner), 4)
        self.assertEqual(len(runner.calls), 2)

    def test_returns_vanished_for_missing_process(self):
        runner = _Runner([{"pid": 400, "address": "0xmissing"}])

        self.assertEqual(focus_session("claude", 400, STARTED_AT, runner), 3)
        self.assertEqual(runner.calls, [])

    def test_returns_vanished_for_reused_pid_start_mismatch(self):
        _write_process(self.proc_root, 500, 1, 350)
        runner = _Runner([{"pid": 500, "address": "0xreused"}])

        self.assertEqual(focus_session("claude", 500, STARTED_AT, runner), 3)
        self.assertEqual(runner.calls, [])

    def test_revalidates_pid_and_start_time_immediately_before_dispatch(self):
        process_dir = _write_process(self.proc_root, 600, 1, 250)
        runner = _Runner([{"pid": 600, "address": "0xraced"}])

        def _reuse_pid():
            fields_before_start = " ".join(["0"] * 17)
            (process_dir / "stat").write_text(
                f"600 (agent process) S 1 {fields_before_start} 350 0 0\n",
                encoding="utf-8",
            )

        runner.after_clients = _reuse_pid

        self.assertEqual(focus_session("claude", 600, STARTED_AT, runner), 3)
        self.assertEqual(len(runner.calls), 2)

    def test_revalidates_pid_replaced_after_terminal_correlation(self):
        process_dir = _write_process(self.proc_root, 625, 600, 250)
        _write_process(self.proc_root, 600, 1, 100)
        runner = _Runner([{"pid": 600, "address": "0xfinal-race"}])
        original_identity = focus_module._agent_identity
        identity_calls = 0

        def _replace_after_penultimate_identity(*args):
            nonlocal identity_calls
            result = original_identity(*args)
            identity_calls += 1
            if identity_calls == 2:
                fields_before_start = " ".join(["0"] * 17)
                (process_dir / "stat").write_text(
                    f"625 (agent process) S 1 {fields_before_start} 350 0 0\n",
                    encoding="utf-8",
                )
            return result

        with mock.patch(
            "lib.agents.focus._agent_identity",
            side_effect=_replace_after_penultimate_identity,
        ):
            result = focus_session("claude", 625, STARTED_AT, runner)

        self.assertEqual(result, 3)
        self.assertEqual(
            [call[0] for call in runner.calls],
            [
                ["tmux", "list-panes", "-a", "-F", "#{pane_pid} #{session_name}"],
                ["hyprctl", "clients", "-j"],
            ],
        )

    def test_does_not_focus_reused_terminal_ancestor(self):
        _write_process(self.proc_root, 650, 625, 250)
        ancestor_dir = _write_process(self.proc_root, 625, 1, 100)
        runner = _Runner([{"pid": 625, "address": "0xunrelated"}])

        def _reuse_ancestor():
            fields_before_start = " ".join(["0"] * 17)
            (ancestor_dir / "stat").write_text(
                f"625 (agent process) S 1 {fields_before_start} 150 0 0\n",
                encoding="utf-8",
            )

        runner.after_clients = _reuse_ancestor

        self.assertEqual(focus_session("claude", 650, STARTED_AT, runner), 4)
        self.assertEqual(
            [call[0] for call in runner.calls],
            [
                ["tmux", "list-panes", "-a", "-F", "#{pane_pid} #{session_name}"],
                ["hyprctl", "clients", "-j"],
            ],
        )

    def test_falls_back_to_valid_farther_ancestor_after_nearest_is_reused(self):
        _write_process(self.proc_root, 675, 650, 250)
        nearest_dir = _write_process(self.proc_root, 650, 625, 100)
        _write_process(self.proc_root, 625, 1, 50)
        runner = _Runner([
            {"pid": 650, "address": "0xunrelated"},
            {"pid": 625, "address": "0xvalid"},
        ])

        def _reuse_nearest():
            fields_before_start = " ".join(["0"] * 17)
            (nearest_dir / "stat").write_text(
                f"650 (agent process) S 625 {fields_before_start} 150 0 0\n",
                encoding="utf-8",
            )

        runner.after_clients = _reuse_nearest

        self.assertEqual(focus_session("claude", 675, STARTED_AT, runner), 0)
        self.assertEqual(
            [call[0] for call in runner.calls],
            [
                ["tmux", "list-panes", "-a", "-F", "#{pane_pid} #{session_name}"],
                ["hyprctl", "clients", "-j"],
                [
                    "hyprctl", "dispatch",
                    'hl.dsp.focus({window = "address:0xvalid"})',
                ],
            ],
        )

    def test_focuses_tmux_hosted_session_via_attached_client(self):
        # claude's pane shell (pid 950) is the direct ancestor tmux spawned;
        # the terminal that owns the window (pid 990) only attaches to that
        # session over the tmux protocol, so it never appears in claude's own
        # /proc ancestor chain — only the tmux bridge can find it.
        _write_process(self.proc_root, 1000, 950, 250)
        _write_process(self.proc_root, 950, 1, 100)
        _write_process(self.proc_root, 990, 1, 50)
        runner = _Runner(
            [{"pid": 990, "address": "0xterminal"}],
            panes="950 mysession\n",
            tmux_clients="990 mysession\n",
        )

        result = focus_session("claude", 1000, STARTED_AT, runner)

        self.assertEqual(result, 0)
        self.assertEqual(
            runner.calls[-1][0],
            [
                "hyprctl", "dispatch",
                'hl.dsp.focus({window = "address:0xterminal"})',
            ],
        )

    def test_ignores_tmux_session_with_no_matching_pane(self):
        _write_process(self.proc_root, 1100, 1, 250)
        runner = _Runner(
            [{"pid": 1100, "address": "0xdirect"}],
            panes="42424 othersession\n",
            tmux_clients="990 othersession\n",
        )

        result = focus_session("claude", 1100, STARTED_AT, runner)

        self.assertEqual(result, 0)
        # The tmux client (990) never gets queried for since no pane in the
        # probe matched claude's own ancestor chain — direct correlation wins.
        self.assertEqual(
            [call[0] for call in runner.calls],
            [
                ["tmux", "list-panes", "-a", "-F", "#{pane_pid} #{session_name}"],
                ["hyprctl", "clients", "-j"],
                [
                    "hyprctl", "dispatch",
                    'hl.dsp.focus({window = "address:0xdirect"})',
                ],
            ],
        )

    def test_returns_command_failure_for_clients_or_dispatch_failure(self):
        _write_process(self.proc_root, 700, 1, 250)

        def _failed_clients(argv, **kwargs):
            return SimpleNamespace(returncode=1, stdout="", stderr="failed")

        self.assertEqual(focus_session("claude", 700, STARTED_AT, _failed_clients), 5)

        runner = _Runner(
            [{"pid": 700, "address": "0xdispatch-failure"}],
            dispatch_returncode=1,
        )
        self.assertEqual(focus_session("claude", 700, STARTED_AT, runner), 5)

    def test_returns_vanished_when_pid_is_not_expected_agent(self):
        _write_process(self.proc_root, 750, 1, 250, agent_id="codex")
        runner = _Runner([{"pid": 750, "address": "0xunrelated"}])

        self.assertEqual(focus_session("claude", 750, STARTED_AT, runner), 3)
        self.assertEqual(runner.calls, [])

    def test_revalidates_agent_identity_immediately_before_dispatch(self):
        process_dir = _write_process(self.proc_root, 800, 1, 250)
        runner = _Runner([{"pid": 800, "address": "0xraced"}])

        def _replace_agent():
            (process_dir / "exe").unlink()
            (process_dir / "exe").symlink_to("/usr/bin/codex")
            (process_dir / "comm").write_text("codex\n", encoding="utf-8")
            (process_dir / "cmdline").write_bytes(b"/usr/bin/codex\0")

        runner.after_clients = _replace_agent

        self.assertEqual(focus_session("claude", 800, STARTED_AT, runner), 3)
        self.assertEqual(len(runner.calls), 2)


if __name__ == "__main__":
    unittest.main()
