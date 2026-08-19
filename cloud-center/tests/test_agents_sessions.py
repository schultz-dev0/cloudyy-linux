from __future__ import annotations

import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

from lib.agents.sessions import scan_sessions


NOW = datetime(2026, 8, 14, 12, 0, tzinfo=timezone.utc)
SESSION_FIELDS = {
    "agentId",
    "agentName",
    "pid",
    "workingDirectory",
    "projectName",
    "startedAt",
    "state",
}


def _write_proc_stat(proc_root: Path, boot_time: int = 1_700_000_000) -> None:
    (proc_root / "stat").write_text(
        f"cpu  1 2 3 4\nbtime {boot_time}\n", encoding="utf-8",
    )


def _write_process(
    proc_root: Path,
    pid: int,
    project: Path,
    *,
    executable: str,
    comm: str | None = None,
    command: list[str] | None = None,
    parent: int = 1,
    start_ticks: int = 0,
) -> Path:
    pid_dir = proc_root / str(pid)
    pid_dir.mkdir()
    (pid_dir / "exe").symlink_to(executable)
    (pid_dir / "comm").write_text(f"{comm or Path(executable).name}\n", encoding="utf-8")
    argv = command or [executable]
    (pid_dir / "cmdline").write_bytes(b"\0".join(value.encode() for value in argv) + b"\0")
    (pid_dir / "cwd").symlink_to(project)
    fields_before_start = " ".join(["0"] * 17)
    (pid_dir / "stat").write_text(
        f"{pid} ({comm or Path(executable).name}) S {parent} "
        f"{fields_before_start} {start_ticks} 0 0\n",
        encoding="utf-8",
    )
    return pid_dir


class AgentsSessionsTest(unittest.TestCase):
    def test_discovers_exact_supported_executables_without_command_lines(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            projects = Path(tmp) / "projects"
            projects.mkdir()
            for offset, executable in enumerate(("claude", "codex", "opencode")):
                project = projects / executable
                project.mkdir()
                _write_process(
                    proc_root,
                    100 + offset,
                    project,
                    executable=f"/usr/bin/{executable}",
                    start_ticks=offset * 100,
                )

            sessions = scan_sessions(proc_root, NOW)

        self.assertEqual(
            [(item["agentId"], item["agentName"]) for item in sessions],
            [("claude", "Claude"), ("codex", "Codex"), ("opencode", "OpenCode")],
        )
        self.assertTrue(all(set(item) == SESSION_FIELDS for item in sessions))
        self.assertTrue(all(item["state"] == "running" for item in sessions))

    def test_exact_comm_and_command_name_are_supported_fallbacks(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            project = Path(tmp) / "project"
            project.mkdir()
            _write_process(
                proc_root,
                200,
                project,
                executable="/usr/bin/node",
                comm="claude",
                command=["/usr/bin/node", "/opt/claude/cli.js"],
            )
            _write_process(
                proc_root,
                201,
                project,
                executable="/usr/bin/node",
                comm="node",
                command=["/usr/bin/codex", "--quiet"],
            )

            sessions = scan_sessions(proc_root, NOW)

        self.assertEqual([item["agentId"] for item in sessions], ["claude", "codex"])

    def test_generic_runtimes_do_not_match_agent_names_in_arguments(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            project = Path(tmp) / "project"
            project.mkdir()
            for pid, runtime, argument in (
                (300, "node", "/opt/claude/cli.js"),
                (301, "python3", "/work/codex.py"),
                (302, "bun", "/work/opencode.ts"),
                (303, "electron", "--app=claude"),
            ):
                _write_process(
                    proc_root,
                    pid,
                    project,
                    executable=f"/usr/bin/{runtime}",
                    command=[runtime, argument],
                )

            self.assertEqual(scan_sessions(proc_root, NOW), [])

    def test_excludes_desktop_app_and_internal_daemon_helper(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            project = Path(tmp) / "project"
            project.mkdir()
            _write_process(
                proc_root, 310, project,
                executable="/usr/lib/claude-desktop-bin/claude",
                command=["/usr/lib/claude-desktop-bin/claude", "--startup"],
            )
            _write_process(
                proc_root, 311, project,
                executable="/home/user/.local/bin/claude",
                command=["/home/user/.local/bin/claude", "daemon", "run"],
            )
            _write_process(
                proc_root, 312, project, executable="/usr/bin/claude",
            )

            sessions = scan_sessions(proc_root, NOW)

        self.assertEqual([item["pid"] for item in sessions], [312])

    def test_deduplicates_recognized_parent_child_tree_to_oldest_ancestor(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            project = Path(tmp) / "my-project"
            project.mkdir()
            _write_process(
                proc_root, 400, project, executable="/usr/bin/claude", start_ticks=100,
            )
            _write_process(
                proc_root,
                401,
                project,
                executable="/opt/claude",
                parent=400,
                start_ticks=200,
            )
            _write_process(
                proc_root,
                402,
                project,
                executable="/usr/bin/codex",
                parent=401,
                start_ticks=300,
            )

            sessions = scan_sessions(proc_root, NOW)

        self.assertEqual([(item["agentId"], item["pid"]) for item in sessions], [
            ("claude", 400),
        ])

    def test_deduplicates_through_unrecognized_intermediate(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            project = Path(tmp) / "project"
            project.mkdir()
            _write_process(
                proc_root, 410, project, executable="/usr/bin/claude", start_ticks=100,
            )
            _write_process(
                proc_root, 411, project, executable="/usr/bin/bash", parent=410,
                start_ticks=200,
            )
            _write_process(
                proc_root, 412, project, executable="/usr/bin/claude", parent=411,
                start_ticks=300,
            )

            sessions = scan_sessions(proc_root, NOW)

        self.assertEqual([(item["agentId"], item["pid"]) for item in sessions], [
            ("claude", 410),
        ])

    def test_keeps_independent_recognized_siblings(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            project = Path(tmp) / "project"
            project.mkdir()
            _write_process(
                proc_root, 420, project, executable="/usr/bin/bash", start_ticks=50,
            )
            _write_process(
                proc_root, 421, project, executable="/usr/bin/claude", parent=420,
                start_ticks=100,
            )
            _write_process(
                proc_root, 422, project, executable="/usr/bin/claude", parent=420,
                start_ticks=200,
            )

            sessions = scan_sessions(proc_root, NOW)

        self.assertEqual([item["pid"] for item in sessions], [421, 422])

    def test_keeps_descendant_when_intermediate_has_vanished(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            project = Path(tmp) / "project"
            project.mkdir()
            _write_process(
                proc_root, 430, project, executable="/usr/bin/claude", start_ticks=100,
            )
            _write_process(
                proc_root, 432, project, executable="/usr/bin/claude", parent=431,
                start_ticks=300,
            )

            sessions = scan_sessions(proc_root, NOW)

        self.assertEqual([item["pid"] for item in sessions], [430, 432])

    def test_malformed_parent_cycle_terminates_and_keeps_oldest_recognized(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            project = Path(tmp) / "project"
            project.mkdir()
            _write_process(
                proc_root, 440, project, executable="/usr/bin/claude", parent=441,
                start_ticks=100,
            )
            _write_process(
                proc_root, 441, project, executable="/usr/bin/bash", parent=442,
                start_ticks=200,
            )
            _write_process(
                proc_root, 442, project, executable="/usr/bin/codex", parent=440,
                start_ticks=300,
            )

            sessions = scan_sessions(proc_root, NOW)

        self.assertEqual([(item["agentId"], item["pid"]) for item in sessions], [
            ("claude", 440),
        ])

    def test_omits_process_reused_while_session_fields_are_read(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            project = Path(tmp) / "project"
            project.mkdir()
            pid_dir = _write_process(
                proc_root, 450, project, executable="/usr/bin/claude", start_ticks=100,
            )
            stable = _write_process(
                proc_root, 451, project, executable="/usr/bin/codex", start_ticks=200,
            )
            real_read_text = Path.read_text
            raced_reads = 0

            def _read_text(path, *args, **kwargs):
                nonlocal raced_reads
                if path == pid_dir / "stat":
                    raced_reads += 1
                    if raced_reads > 1:
                        return real_read_text(stable / "stat", *args, **kwargs).replace(
                            "451 (codex)", "450 (claude)",
                        )
                return real_read_text(path, *args, **kwargs)

            with mock.patch.object(Path, "read_text", _read_text):
                sessions = scan_sessions(proc_root, NOW)

        self.assertGreaterEqual(raced_reads, 2)
        self.assertEqual([item["pid"] for item in sessions], [451])

    def test_uses_boot_time_and_clock_ticks_for_start_time_and_oldest_first_sort(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root, boot_time=1_700_000_000)
            project = Path(tmp) / "project"
            project.mkdir()
            _write_process(
                proc_root, 500, project, executable="/usr/bin/codex", start_ticks=250,
            )
            _write_process(
                proc_root, 501, project, executable="/usr/bin/claude", start_ticks=100,
            )

            with mock.patch("lib.agents.sessions.os.sysconf", return_value=100):
                sessions = scan_sessions(proc_root, NOW)

        self.assertEqual([item["pid"] for item in sessions], [501, 500])
        self.assertEqual(sessions[0]["startedAt"], "2023-11-14T22:13:21+00:00")
        self.assertEqual(sessions[1]["startedAt"], "2023-11-14T22:13:22.500000+00:00")

    def test_isolates_pid_races_permission_errors_and_malformed_stats(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            project = Path(tmp) / "survivor"
            project.mkdir()
            _write_process(proc_root, 600, project, executable="/usr/bin/claude")
            raced = _write_process(proc_root, 601, project, executable="/usr/bin/codex")
            (raced / "stat").unlink()
            denied = _write_process(proc_root, 602, project, executable="/usr/bin/opencode")
            malformed = _write_process(proc_root, 603, project, executable="/usr/bin/codex")
            (malformed / "stat").write_text("603 (codex) broken\n", encoding="utf-8")
            _write_process(
                proc_root,
                604,
                project,
                executable="/usr/bin/opencode",
                start_ticks=10**30,
            )
            _write_process(
                proc_root,
                605,
                project,
                executable="/usr/bin/codex",
                start_ticks=-1,
            )
            real_read_text = Path.read_text

            def _read_text(path, *args, **kwargs):
                if path == denied / "stat":
                    raise PermissionError("denied fake proc entry")
                return real_read_text(path, *args, **kwargs)

            with mock.patch.object(Path, "read_text", _read_text):
                sessions = scan_sessions(proc_root, NOW)

        self.assertEqual([item["pid"] for item in sessions], [600])

    def test_does_not_depend_on_pid_directory_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            project = Path(tmp) / "project"
            project.mkdir()
            _write_process(proc_root, 650, project, executable="/usr/bin/claude")

            with mock.patch.object(
                Path, "is_dir", side_effect=PermissionError("raced proc metadata"),
            ):
                sessions = scan_sessions(proc_root, NOW)

        self.assertEqual([item["pid"] for item in sessions], [650])

    def test_skips_process_when_working_directory_is_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            project = Path(tmp) / "project"
            project.mkdir()
            pid_dir = _write_process(
                proc_root, 700, project, executable="/usr/bin/claude",
            )
            (pid_dir / "cwd").unlink()

            self.assertEqual(scan_sessions(proc_root, NOW), [])

    def test_project_name_uses_working_directory_basename(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            _write_proc_stat(proc_root)
            project = Path(tmp) / "cloudyy-linux"
            project.mkdir()
            _write_process(proc_root, 800, project, executable="/usr/bin/opencode")

            sessions = scan_sessions(proc_root, NOW)

        self.assertEqual(sessions[0]["workingDirectory"], os.fspath(project))
        self.assertEqual(sessions[0]["projectName"], "cloudyy-linux")

    def test_malformed_global_proc_stat_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc_root = Path(tmp) / "proc"
            proc_root.mkdir()
            (proc_root / "stat").write_text("cpu 1 2 3 4\n", encoding="utf-8")
            project = Path(tmp) / "project"
            project.mkdir()
            _write_process(proc_root, 900, project, executable="/usr/bin/claude")

            self.assertEqual(scan_sessions(proc_root, NOW), [])


if __name__ == "__main__":
    unittest.main()
