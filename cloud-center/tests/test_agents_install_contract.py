from __future__ import annotations

import io
import json
import os
import subprocess
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path


from lib.agents.cli import main
from lib.agents.contract import write_record


NOW = datetime(2026, 8, 14, 12, 0, tzinfo=timezone.utc)
ROOT = Path(__file__).resolve().parents[2]


def _record(provider: str, used_percent: int = 25) -> dict:
    name = provider.title()
    return {
        "schemaVersion": 1,
        "recordId": provider,
        "provider": {"id": provider, "name": name},
        "planLabel": "Plus",
        "allowances": [{
            "id": "session",
            "label": "Session",
            "usedPercent": used_percent,
            "resetAt": "2026-08-15T12:00:00+00:00",
        }],
        "dataUpdatedAt": NOW.isoformat(),
        "lastAttemptAt": NOW.isoformat(),
        "status": {"state": "ok", "message": ""},
    }


class AgentsCliTest(unittest.TestCase):
    def test_snapshot_combines_valid_usage_and_injected_sessions(self):
        sessions = [{
            "agentId": "codex",
            "agentName": "Codex",
            "pid": 42,
            "workingDirectory": "/work/project",
            "projectName": "project",
            "startedAt": "2026-08-14T11:00:00+00:00",
            "state": "running",
        }]
        with tempfile.TemporaryDirectory() as tmp:
            usage_dir = Path(tmp)
            (usage_dir / "claude.json").write_text(
                json.dumps(_record("claude")), encoding="utf-8",
            )
            (usage_dir / "invalid.json").write_text("not json", encoding="utf-8")
            output = io.StringIO()

            result = main(
                ["snapshot", "--json"],
                now=lambda: NOW,
                usage_dir=usage_dir,
                session_scanner=lambda: sessions,
                stdout=output,
            )

        self.assertEqual(result, 0)
        self.assertEqual(json.loads(output.getvalue()), {
            "usage": [{**_record("claude"), "stale": False}],
            "sessions": sessions,
        })

    def test_collect_isolates_provider_exceptions_and_persists_peers(self):
        calls = []

        def failed():
            calls.append("claude")
            raise RuntimeError("secret provider response")

        def successful():
            calls.append("codex")
            return _record("codex", 60)

        with tempfile.TemporaryDirectory() as tmp:
            usage_dir = Path(tmp)
            result = main(
                ["collect"],
                now=lambda: NOW,
                usage_dir=usage_dir,
                providers={"claude": failed, "codex": successful},
                stdout=io.StringIO(),
                stderr=io.StringIO(),
            )
            claude = json.loads((usage_dir / "claude.json").read_text(encoding="utf-8"))
            codex = json.loads((usage_dir / "codex.json").read_text(encoding="utf-8"))

        self.assertEqual(result, 1)
        self.assertEqual(calls, ["claude", "codex"])
        self.assertEqual(claude["status"], {
            "state": "error", "message": "Collection failed",
        })
        self.assertEqual(codex, _record("codex", 60))
        self.assertNotIn("secret", repr(claude))

    def test_collect_provider_option_runs_only_selected_provider(self):
        calls = []
        providers = {
            name: lambda name=name: calls.append(name) or _record(name)
            for name in ("claude", "codex", "fireworks")
        }
        with tempfile.TemporaryDirectory() as tmp:
            result = main(
                ["collect", "--provider", "codex"],
                now=lambda: NOW,
                usage_dir=Path(tmp),
                providers=providers,
                stdout=io.StringIO(),
                stderr=io.StringIO(),
            )

        self.assertEqual(result, 0)
        self.assertEqual(calls, ["codex"])

    def test_collect_error_record_does_not_prevent_peer_collection(self):
        failed = _record("claude")
        failed["status"] = {"state": "error", "message": "Collection failed"}
        calls = []
        with tempfile.TemporaryDirectory() as tmp:
            result = main(
                ["collect"],
                now=lambda: NOW,
                usage_dir=Path(tmp),
                providers={
                    "claude": lambda: calls.append("claude") or failed,
                    "codex": lambda: calls.append("codex") or _record("codex"),
                },
                stdout=io.StringIO(),
                stderr=io.StringIO(),
            )

        self.assertEqual(result, 1)
        self.assertEqual(calls, ["claude", "codex"])

    def test_collect_isolates_all_provider_write_failures(self):
        for collector_fails, expected_claude_writes in ((False, 2), (True, 1)):
            with self.subTest(collector_fails=collector_fails):
                calls = []
                writes = []

                def claude():
                    calls.append("claude")
                    if collector_fails:
                        raise RuntimeError("private collector failure")
                    return _record("claude")

                def codex():
                    calls.append("codex")
                    return _record("codex", 60)

                def writer(path, record):
                    writes.append((path.name, record["status"]["state"]))
                    if path.name == "claude.json":
                        raise OSError("unwritable provider path")
                    write_record(path, record)

                with tempfile.TemporaryDirectory() as tmp:
                    usage_dir = Path(tmp)
                    result = main(
                        ["collect"],
                        now=lambda: NOW,
                        usage_dir=usage_dir,
                        providers={"claude": claude, "codex": codex},
                        record_writer=writer,
                        stdout=io.StringIO(),
                        stderr=io.StringIO(),
                    )
                    codex_record = json.loads(
                        (usage_dir / "codex.json").read_text(encoding="utf-8"),
                    )

                self.assertEqual(result, 1)
                self.assertEqual(calls, ["claude", "codex"])
                self.assertEqual(
                    sum(name == "claude.json" for name, _ in writes),
                    expected_claude_writes,
                )
                self.assertEqual(codex_record, _record("codex", 60))

    def test_sessions_and_focus_use_injected_dependencies(self):
        sessions = [{"pid": 17}]
        output = io.StringIO()
        self.assertEqual(main(
            ["sessions", "--json"],
            session_scanner=lambda: sessions,
            stdout=output,
        ), 0)
        self.assertEqual(json.loads(output.getvalue()), sessions)

        focus_calls = []
        result = main(
            [
                "focus", "--agent-id", "codex", "--pid", "17",
                "--started-at", "2026-08-14T11:00:00+00:00",
            ],
            focuser=lambda agent_id, pid, started_at: focus_calls.append(
                (agent_id, pid, started_at)
            ) or 4,
            stdout=io.StringIO(),
        )
        self.assertEqual(result, 4)
        self.assertEqual(focus_calls, [
            ("codex", 17, "2026-08-14T11:00:00+00:00"),
        ])


class AgentsInstallTest(unittest.TestCase):
    def test_launcher_executes_cli_from_repo_cloud_center(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_bin = Path(tmp)
            log = fake_bin / "python.log"
            python = fake_bin / "python3"
            python.write_text(
                "#!/usr/bin/env bash\nprintf '%s\\n' \"$PWD\" \"$*\" >\"$PYTHON_LOG\"\n",
                encoding="utf-8",
            )
            python.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}:{env['PATH']}"
            env["PYTHON_LOG"] = os.fspath(log)

            completed = subprocess.run(
                [ROOT / "bin/cloudyy-agents", "snapshot", "--json"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            lines = log.read_text(encoding="utf-8").splitlines()
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(lines, [
            os.fspath(ROOT / "cloud-center"),
            "-m lib.agents.cli snapshot --json",
        ])

    def test_launcher_resolves_relative_installed_symlink_to_repo(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            installed_bin = root / "home/.local/bin"
            fake_bin = root / "fake-bin"
            installed_bin.mkdir(parents=True)
            fake_bin.mkdir()
            log = root / "python.log"
            python = fake_bin / "python3"
            python.write_text(
                "#!/usr/bin/env bash\nprintf '%s\\n' \"$PWD\" \"$*\" >\"$PYTHON_LOG\"\n",
                encoding="utf-8",
            )
            python.chmod(0o755)
            launcher = installed_bin / "cloudyy-agents"
            launcher.symlink_to(os.path.relpath(ROOT / "bin/cloudyy-agents", installed_bin))
            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}:{env['PATH']}"
            env["PYTHON_LOG"] = os.fspath(log)

            completed = subprocess.run(
                [launcher, "sessions", "--json"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            lines = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(lines, [
            os.fspath(ROOT / "cloud-center"),
            "-m lib.agents.cli sessions --json",
        ])

    def test_systemd_units_define_persistent_five_minute_collection(self):
        service = (ROOT / "install/assets/systemd/cloudyy-agent-usage.service").read_text(
            encoding="utf-8",
        )
        timer = (ROOT / "install/assets/systemd/cloudyy-agent-usage.timer").read_text(
            encoding="utf-8",
        )

        self.assertIn("Type=oneshot", service)
        self.assertIn(
            "ExecStart=/usr/bin/bash -lc 'exec \"%h/cloudyy-linux/bin/cloudyy-agents\" collect'",
            service,
        )
        self.assertIn("OnCalendar=*:0/5", timer)
        self.assertNotIn("OnBootSec=", timer)
        self.assertNotIn("OnUnitActiveSec=", timer)
        self.assertIn("Persistent=true", timer)
        self.assertIn("WantedBy=timers.target", timer)

        calendar = subprocess.run(
            ["systemd-analyze", "calendar", "*:0/5"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(calendar.returncode, 0, calendar.stderr)
        self.assertIn("Normalized form: *-*-* *:00/5:00", calendar.stdout)

    def test_installer_enables_only_agent_usage_timer_among_new_units(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / "home"
            fake_bin = root / "bin"
            home.mkdir()
            fake_bin.mkdir()
            systemctl_log = root / "systemctl.log"
            for name, body in {
                "bash": "#!/usr/bin/bash\nexit 0\n",
                "sudo": "#!/usr/bin/bash\nexit 0\n",
                "systemctl": (
                    "#!/usr/bin/bash\nprintf '%s\\n' \"$*\" >>\"$SYSTEMCTL_LOG\"\n"
                ),
            }.items():
                path = fake_bin / name
                path.write_text(body, encoding="utf-8")
                path.chmod(0o755)
            env = os.environ.copy()
            env["HOME"] = os.fspath(home)
            env["PATH"] = f"{fake_bin}:/usr/bin:/bin"
            env["SYSTEMCTL_LOG"] = os.fspath(systemctl_log)

            completed = subprocess.run(
                ["/usr/bin/bash", ROOT / "install/user/all.sh"],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            calls = systemctl_log.read_text(encoding="utf-8").splitlines()

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("--user daemon-reload", calls)
        self.assertIn("--user enable --now cloudyy-agent-usage.timer", calls)
        new_enable_calls = [call for call in calls if "cloudyy-agent-usage" in call]
        self.assertEqual(new_enable_calls, [
            "--user enable --now cloudyy-agent-usage.timer",
        ])


if __name__ == "__main__":
    unittest.main()
