from __future__ import annotations

import json
import hashlib
import os
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path


TIMER = Path(__file__).resolve().parents[2] / "bin" / "cloudyy-timer"


class CloudyyTimerCliTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.state_home = self.root / "state"
        self.data_home = self.root / "data"
        self.home.mkdir()
        self.state_home.mkdir()
        self.data_home.mkdir()
        self.fake_bin = self.state_home / "fake-bin"
        self.fake_bin.mkdir()
        self.systemd_run_log = self.root / "systemd-run.log"
        self.systemctl_log = self.root / "systemctl.log"
        self.notify_log = self.root / "notify.log"
        self.env = os.environ.copy()
        self.env.update({
            "HOME": str(self.home),
            "XDG_STATE_HOME": str(self.state_home),
            "XDG_DATA_HOME": str(self.data_home),
            "CLOUDYY_TIMER_NOW": "1700000000",
            "CLOUDYY_TIMER_SYSTEMD_RUN": "/bin/false",
            "CLOUDYY_TIMER_SYSTEMCTL": "/bin/false",
            "CLOUDYY_TIMER_NOTIFY_SEND": "/bin/false",
            "TZ": "UTC",
        })
        self._install_side_effect_fakes()

    def _run(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [TIMER, *args],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def _set_now(self, value: int):
        self.env["CLOUDYY_TIMER_NOW"] = str(value)

    def _json_timer(self, *args: str) -> dict:
        result = self._run(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def _listed_timers(self) -> list[dict]:
        return self._json_timer("list", "--json")["timers"]

    def _install_fake(self, name: str, log: Path, exit_variable: str):
        executable = self.fake_bin / name
        executable.write_text(
            "#!/usr/bin/env bash\n"
            f"printf '%s\\n' \"$@\" >> {shlex.quote(str(log))}\n"
            f"stderr_variable={shlex.quote(exit_variable.replace('_EXIT', '_STDERR'))}\n"
            "if [[ -n ${!stderr_variable:-} ]]; then\n"
            "  printf '%s\\n' \"${!stderr_variable}\" >&2\n"
            "fi\n"
            f"exit \"${{{exit_variable}:-0}}\"\n",
            encoding="utf-8",
        )
        executable.chmod(0o755)
        return executable

    def _install_deterministic_id_commands(self):
        date = self.fake_bin / "date"
        date.write_text(
            "#!/usr/bin/env bash\n"
            "if [[ $1 == '+%s%N' ]]; then\n"
            "  printf '1700000000123456789\\n'\n"
            "else\n"
            "  exec /usr/bin/date \"$@\"\n"
            "fi\n",
            encoding="utf-8",
        )
        date.chmod(0o755)
        od = self.fake_bin / "od"
        od.write_text(
            "#!/usr/bin/env bash\nprintf ' a1 b2 c3 d4\\n'\n",
            encoding="utf-8",
        )
        od.chmod(0o755)
        self.env["PATH"] = f"{self.fake_bin}:{self.env['PATH']}"

    def _install_side_effect_fakes(self):
        self.env["CLOUDYY_TIMER_SYSTEMD_RUN"] = str(self._install_fake(
            "systemd-run", self.systemd_run_log, "FAKE_SYSTEMD_RUN_EXIT"
        ))
        self.env["CLOUDYY_TIMER_SYSTEMCTL"] = str(self._install_fake(
            "systemctl", self.systemctl_log, "FAKE_SYSTEMCTL_EXIT"
        ))
        self.env["CLOUDYY_TIMER_NOTIFY_SEND"] = str(self._install_fake(
            "notify-send", self.notify_log, "FAKE_NOTIFY_EXIT"
        ))

    def _write_legacy(self, document: dict) -> tuple[Path, bytes]:
        source = self.data_home / "quickshell" / "timer" / "active.json"
        source.parent.mkdir(parents=True)
        source_bytes = json.dumps(document, separators=(",", ":")).encode()
        source.write_bytes(source_bytes)
        return source, source_bytes

    def _migration_marker(self) -> dict:
        marker = self.state_home / "cloudyy" / "timers" / "migration-v1.json"
        return json.loads(marker.read_text(encoding="utf-8"))

    def _state_file(self) -> Path:
        return self.state_home / "cloudyy" / "timers" / "state.json"

    def _write_state(self, document: dict) -> bytes:
        state_file = self._state_file()
        state_file.parent.mkdir(parents=True, exist_ok=True)
        state_bytes = json.dumps(document, separators=(",", ":")).encode()
        state_file.write_bytes(state_bytes)
        (state_file.parent / "migration-v1.json").write_text(
            '{"version":1,"status":"test"}\n', encoding="utf-8"
        )
        return state_bytes

    def test_empty_list_initializes_private_state_and_emits_json_contract(self):
        result = self._run("list", "--json")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(result.stdout),
            {"version": 1, "generated_at": 1700000000, "timers": []},
        )
        state_dir = self.state_home / "cloudyy" / "timers"
        state_file = state_dir / "state.json"
        self.assertEqual(
            json.loads(state_file.read_text(encoding="utf-8")),
            {"version": 1, "updated_at": 1700000000, "timers": []},
        )
        self.assertEqual(state_file.stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(self.home.iterdir()), [])
        self.assertEqual(list(self.data_home.iterdir()), [])
        self.assertEqual(
            {path.relative_to(self.root).parts[0] for path in self.root.rglob("*")},
            {"home", "state", "data"},
        )

    def test_empty_list_supports_human_readable_output(self):
        result = self._run("list")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "No timers.\n")

    def test_nonempty_list_supports_human_readable_derived_output(self):
        self._json_timer(
            "create", "--label", "Tea", "--duration", "90", "--json"
        )
        self._json_timer("stopwatch-start", "--label", "Lap", "--json")
        self._set_now(1700000030)

        result = self._run("list")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "Tea | countdown | running | 60s remaining\n"
            "Lap | stopwatch | running | 30s elapsed\n",
        )
        with self.assertRaises(json.JSONDecodeError):
            json.loads(result.stdout)

    def test_invalid_duration_exits_with_usage_status(self):
        result = self._run("create", "--label", "Tea", "--duration", "later")

        self.assertEqual(result.returncode, 2, result.stderr)

    def test_create_rejects_missing_empty_duplicate_and_extra_arguments(self):
        invalid_arguments = [
            ("--duration", "60"),
            ("--label",),
            ("--label", "Tea"),
            ("--label", "", "--duration", "60"),
            ("--label", "--duration", "60"),
            ("--label", "Tea", "--label", "Coffee", "--duration", "60"),
            ("--label", "Tea", "--duration"),
            ("--label", "Tea", "--duration", "60", "--duration", "90"),
            ("--label", "Tea", "--duration", "60", "--json", "--json"),
            ("--label", "Tea", "--duration", "60", "extra"),
        ]

        for arguments in invalid_arguments:
            with self.subTest(arguments=arguments):
                result = self._run("create", *arguments)
                self.assertEqual(result.returncode, 2, result.stderr)

    def test_stopwatch_start_rejects_invalid_arguments(self):
        invalid_arguments = [
            (),
            ("--label",),
            ("--label", ""),
            ("--label", "--json"),
            ("--label", "Lap", "--label", "Race"),
            ("--label", "Lap", "--json", "--json"),
            ("--label", "Lap", "extra"),
            ("--duration", "60"),
        ]

        for arguments in invalid_arguments:
            with self.subTest(arguments=arguments):
                result = self._run("stopwatch-start", *arguments)
                self.assertEqual(result.returncode, 2, result.stderr)

    def test_valid_create_and_stopwatch_start_succeed(self):
        commands = [
            ("create", "--label", "Tea", "--duration", "60", "--json"),
            ("stopwatch-start", "--label", "Lap", "--json"),
        ]

        for command in commands:
            with self.subTest(command=command):
                result = self._run(*command)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_corrupt_state_is_rejected_without_rewriting_it(self):
        state_dir = self.state_home / "cloudyy" / "timers"
        state_dir.mkdir(parents=True)
        state_file = state_dir / "state.json"
        corrupt_bytes = b'{"version":1,"timers":[broken]\n'
        state_file.write_bytes(corrupt_bytes)

        result = self._run("list", "--json")

        self.assertEqual(result.returncode, 5, result.stderr)
        self.assertEqual(state_file.read_bytes(), corrupt_bytes)

    def test_unknown_id_exits_with_unknown_id_status(self):
        result = self._run("pause", "missing-timer")

        self.assertEqual(result.returncode, 3, result.stderr)

    def test_countdown_create_pause_resume_reset_and_delete(self):
        timer = self._json_timer(
            "create", "--label", "Tea", "--duration", "90", "--json"
        )
        timer_id = timer["id"]
        self.assertRegex(timer_id, r"^ct-\d{19}-[0-9a-f]{8}$")
        self.assertEqual(
            timer,
            {
                "id": timer_id,
                "label": "Tea",
                "mode": "countdown",
                "state": "running",
                "duration_seconds": 90,
                "elapsed_seconds": 0,
                "remaining_seconds": 90,
                "created_at": 1700000000,
                "transitioned_at": 1700000000,
                "deadline_at": 1700000090,
            },
        )

        self._set_now(1700000030)
        self.assertEqual(self._listed_timers()[0]["remaining_seconds"], 60)
        paused = self._json_timer("pause", timer_id)
        self.assertEqual(paused["state"], "paused")
        self.assertEqual(paused["elapsed_seconds"], 30)
        self.assertEqual(paused["remaining_seconds"], 60)
        self._set_now(1700000035)
        self.assertEqual(self._json_timer("pause", timer_id), paused)

        self._set_now(1700000040)
        resumed = self._json_timer("resume", timer_id)
        self.assertEqual(resumed["state"], "running")
        self.assertEqual(resumed["deadline_at"], 1700000100)
        self.assertEqual(resumed["remaining_seconds"], 60)
        self._set_now(1700000045)
        resumed_again = self._json_timer("resume", timer_id)
        self.assertEqual(resumed_again["transitioned_at"], 1700000040)
        self.assertEqual(resumed_again["deadline_at"], 1700000100)
        self.assertEqual(resumed_again["remaining_seconds"], 55)

        self._set_now(1700000050)
        reset = self._json_timer("reset", timer_id)
        self.assertEqual(reset["state"], "running")
        self.assertEqual(reset["elapsed_seconds"], 0)
        self.assertEqual(reset["remaining_seconds"], 90)
        self.assertEqual(reset["deadline_at"], 1700000140)
        self.assertEqual(self._json_timer("reset", timer_id), reset)

        deleted = self._json_timer("delete", timer_id)
        self.assertEqual(deleted, reset)
        self.assertEqual(self._listed_timers(), [])

    def test_persisted_active_records_omit_derived_display_fields(self):
        self._json_timer("create", "--label", "Tea", "--duration", "90", "--json")
        self._json_timer("stopwatch-start", "--label", "Lap", "--json")

        records = json.loads(self._state_file().read_text(encoding="utf-8"))["timers"]

        for record in records:
            with self.subTest(timer_id=record["id"]):
                self.assertNotIn("elapsed_seconds", record)
                self.assertNotIn("remaining_seconds", record)

    def test_stopwatch_start_pause_resume_reset_delete_and_clock_jump(self):
        timer = self._json_timer("stopwatch-start", "--label", "Lap", "--json")
        timer_id = timer["id"]
        self.assertRegex(timer_id, r"^sw-\d{19}-[0-9a-f]{8}$")
        self.assertEqual(
            timer,
            {
                "id": timer_id,
                "label": "Lap",
                "mode": "stopwatch",
                "state": "running",
                "duration_seconds": None,
                "elapsed_seconds": 0,
                "remaining_seconds": None,
                "created_at": 1700000000,
                "transitioned_at": 1700000000,
                "deadline_at": None,
            },
        )

        self._set_now(1699999990)
        self.assertEqual(self._listed_timers()[0]["elapsed_seconds"], 0)
        self._set_now(1700000025)
        paused = self._json_timer("stopwatch-pause", timer_id)
        self.assertEqual(paused["state"], "paused")
        self.assertEqual(paused["elapsed_seconds"], 25)
        self._set_now(1700000030)
        self.assertEqual(self._json_timer("stopwatch-pause", timer_id), paused)

        self._set_now(1700000040)
        resumed = self._json_timer("resume", timer_id)
        self.assertEqual(resumed["state"], "running")
        self.assertEqual(resumed["elapsed_seconds"], 25)
        self._set_now(1700000045)
        resumed_again = self._json_timer("resume", timer_id)
        self.assertEqual(resumed_again["transitioned_at"], 1700000040)
        self.assertEqual(resumed_again["elapsed_seconds"], 30)
        self._set_now(1700000050)
        self.assertEqual(self._listed_timers()[0]["elapsed_seconds"], 35)

        reset = self._json_timer("stopwatch-reset", timer_id)
        self.assertEqual(reset["state"], "running")
        self.assertEqual(reset["elapsed_seconds"], 0)
        self.assertEqual(reset["transitioned_at"], 1700000050)
        self.assertEqual(self._json_timer("stopwatch-reset", timer_id), reset)

        deleted = self._json_timer("delete", timer_id)
        self.assertEqual(deleted, reset)
        self.assertEqual(self._listed_timers(), [])

    def test_stop_finishes_and_logs_running_or_paused_stopwatch_without_notification(self):
        for state in ("running", "paused"):
            with self.subTest(state=state):
                self._set_now(1700000000)
                timer = self._json_timer(
                    "stopwatch-start", "--label", f"Lap {state}", "--json"
                )
                self._set_now(1700000030)
                if state == "paused":
                    self._json_timer("stopwatch-pause", timer["id"])

                stopped = self._json_timer("stop", timer["id"], "--json")

                self.assertEqual(stopped["elapsed_seconds"], 30)
                self.assertNotIn(timer["id"], {item["id"] for item in self._listed_timers()})
        history = self.home / "Desktop" / "timer_record" / "2023-11.md"
        history_text = history.read_text(encoding="utf-8")
        self.assertEqual(history_text.count("| stopwatch |"), 2)
        self.assertFalse(self.notify_log.exists())

    def test_rename_updates_label_without_changing_timer_transition(self):
        timer = self._json_timer(
            "create", "--label", "Tea", "--duration", "90", "--json"
        )
        self._set_now(1700000030)

        renamed = self._json_timer("rename", timer["id"], "Coffee")

        self.assertEqual(renamed["label"], "Coffee")
        self.assertEqual(renamed["transitioned_at"], 1700000000)
        self.assertEqual(renamed["remaining_seconds"], 60)

    def test_systemd_schedule_uses_exact_unit_and_absolute_provider(self):
        self._install_side_effect_fakes()
        self._install_deterministic_id_commands()

        timer = self._json_timer(
            "create", "--label", "Tea", "--duration", "90", "--json"
        )

        timer_id = "ct-1700000000123456789-a1b2c3d4"
        self.assertEqual(timer["id"], timer_id)
        self.assertEqual(
            self.systemd_run_log.read_text(encoding="utf-8").splitlines(),
            [
                "--user", "--quiet", "--collect",
                f"--unit=cloudyy-timer-{timer_id}", "--on-calendar=@1700000090",
                "--timer-property=Persistent=true", "--property=Type=oneshot",
                "--property=Restart=on-failure", "--property=RestartSec=5s",
                "--property=StartLimitIntervalSec=5min",
                "--property=StartLimitBurst=5", "--", str(TIMER.resolve()),
                "complete", timer_id,
            ],
        )

    def test_create_write_failure_cancels_new_units_and_leaves_state_absent(self):
        self._install_deterministic_id_commands()
        self.env["CLOUDYY_TIMER_FAIL_STATE_WRITE_AT"] = "1"

        result = self._run("create", "--label", "Tea", "--duration", "90")

        self.assertEqual(result.returncode, 6, result.stderr)
        timer_id = "ct-1700000000123456789-a1b2c3d4"
        self.assertEqual(
            self.systemctl_log.read_text(encoding="utf-8").splitlines(),
            ["--user", "stop", f"cloudyy-timer-{timer_id}.timer",
             f"cloudyy-timer-{timer_id}.service"],
        )
        self.env.pop("CLOUDYY_TIMER_FAIL_STATE_WRITE_AT")
        self.assertEqual(self._listed_timers(), [])

    def test_resume_write_failure_cancels_new_units_and_remains_paused(self):
        timer = self._json_timer("create", "--label", "Tea", "--duration", "90")
        self._set_now(1700000030)
        self._json_timer("pause", timer["id"])
        self.systemctl_log.unlink()
        self.env["CLOUDYY_TIMER_FAIL_STATE_WRITE_AT"] = "1"

        result = self._run("resume", timer["id"])

        self.assertEqual(result.returncode, 6, result.stderr)
        self.assertEqual(
            self.systemctl_log.read_text(encoding="utf-8").splitlines(),
            ["--user", "stop", f"cloudyy-timer-{timer['id']}.timer",
             f"cloudyy-timer-{timer['id']}.service"],
        )
        self.env.pop("CLOUDYY_TIMER_FAIL_STATE_WRITE_AT")
        self.assertEqual(self._listed_timers()[0]["state"], "paused")

    def test_reset_final_write_failure_cancels_new_units_and_remains_paused(self):
        timer = self._json_timer("create", "--label", "Tea", "--duration", "90")
        self._set_now(1700000030)
        self.systemctl_log.unlink(missing_ok=True)
        self.env["CLOUDYY_TIMER_FAIL_STATE_WRITE_AT"] = "2"

        result = self._run("reset", timer["id"])

        self.assertEqual(result.returncode, 6, result.stderr)
        calls = self.systemctl_log.read_text(encoding="utf-8").splitlines()
        expected = ["--user", "stop", f"cloudyy-timer-{timer['id']}.timer",
                    f"cloudyy-timer-{timer['id']}.service"]
        self.assertEqual(calls, expected * 2)
        self.env.pop("CLOUDYY_TIMER_FAIL_STATE_WRITE_AT")
        persisted = self._listed_timers()[0]
        self.assertEqual(persisted["state"], "paused")
        self.assertEqual(persisted["remaining_seconds"], 60)

    def test_schedule_failure_never_persists_running_timer(self):
        self._install_side_effect_fakes()
        self.env["FAKE_SYSTEMD_RUN_EXIT"] = "1"

        result = self._run("create", "--label", "Tea", "--duration", "90")

        self.assertEqual(result.returncode, 7, result.stderr)
        self.env["FAKE_SYSTEMD_RUN_EXIT"] = "0"
        self.assertEqual(self._listed_timers(), [])

    def test_reset_schedule_failure_rolls_back_to_paused_state(self):
        timer = self._json_timer(
            "create", "--label", "Tea", "--duration", "90", "--json"
        )
        self._set_now(1700000030)
        self.env["FAKE_SYSTEMD_RUN_EXIT"] = "1"

        result = self._run("reset", timer["id"])

        self.assertEqual(result.returncode, 7, result.stderr)
        self.env["FAKE_SYSTEMD_RUN_EXIT"] = "0"
        persisted = self._listed_timers()[0]
        self.assertEqual(persisted["state"], "paused")
        self.assertEqual(persisted["remaining_seconds"], 60)

    def test_systemd_countdown_mutations_stop_matching_timer_and_service_units(self):
        self._install_side_effect_fakes()
        timer = self._json_timer(
            "create", "--label", "Tea", "--duration", "90", "--json"
        )
        unit = f"cloudyy-timer-{timer['id']}"

        paused = self._run("pause", timer["id"])
        resumed = self._run("resume", timer["id"])
        reset = self._run("reset", timer["id"])
        deleted = self._run("delete", timer["id"])

        for result in (paused, resumed, reset, deleted):
            self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.systemctl_log.read_text(encoding="utf-8").splitlines()
        expected = ["--user", "stop", f"{unit}.timer", f"{unit}.service"]
        self.assertEqual(calls, expected * 3)

    def test_completed_countdown_resets_when_collected_units_are_not_loaded(self):
        timer = self._json_timer(
            "create", "--label", "Tea", "--duration", "90", "--json"
        )
        self._json_timer("complete", timer["id"], "--json")
        self.env["FAKE_SYSTEMCTL_EXIT"] = "5"
        self.env["FAKE_SYSTEMCTL_STDERR"] = (
            f"Failed to stop cloudyy-timer-{timer['id']}.timer: Unit "
            f"cloudyy-timer-{timer['id']}.timer not loaded.\n"
            f"Failed to stop cloudyy-timer-{timer['id']}.service: Unit "
            f"cloudyy-timer-{timer['id']}.service not loaded."
        )

        reset = self._json_timer("reset", timer["id"])

        self.assertEqual(reset["state"], "running")
        self.assertEqual(reset["remaining_seconds"], 90)
        self.assertEqual(reset["deadline_at"], 1700000090)

    def test_completed_countdown_deletes_when_collected_units_are_not_loaded(self):
        timer = self._json_timer(
            "create", "--label", "Tea", "--duration", "90", "--json"
        )
        completed = self._json_timer("complete", timer["id"], "--json")
        self.env["FAKE_SYSTEMCTL_EXIT"] = "5"
        self.env["FAKE_SYSTEMCTL_STDERR"] = (
            f"Failed to stop cloudyy-timer-{timer['id']}.timer: Unit "
            f"cloudyy-timer-{timer['id']}.timer not loaded.\n"
            f"Failed to stop cloudyy-timer-{timer['id']}.service: Unit "
            f"cloudyy-timer-{timer['id']}.service not loaded."
        )

        deleted = self._json_timer("delete", timer["id"])

        self.assertEqual(deleted, completed)
        self.assertEqual(self._listed_timers(), [])

    def test_systemctl_genuine_failure_preserves_systemd_exit_status(self):
        timer = self._json_timer(
            "create", "--label", "Tea", "--duration", "90", "--json"
        )
        self.env["FAKE_SYSTEMCTL_EXIT"] = "1"
        self.env["FAKE_SYSTEMCTL_STDERR"] = "Failed to connect to bus: Permission denied"

        result = self._run("delete", timer["id"])

        self.assertEqual(result.returncode, 7, result.stderr)
        self.env["FAKE_SYSTEMCTL_EXIT"] = "0"
        self.env.pop("FAKE_SYSTEMCTL_STDERR")
        self.assertEqual(self._listed_timers()[0]["id"], timer["id"])

    def test_complete_retries_only_missing_history_and_notification_effects(self):
        self._install_side_effect_fakes()
        timer = self._json_timer(
            "create", "--label", "Tea | focus", "--duration", "90", "--json"
        )
        self.env["FAKE_NOTIFY_EXIT"] = "1"

        first = self._run("complete", timer["id"], "--json")

        self.assertEqual(first.returncode, 8, first.stderr)
        history = self.home / "Desktop" / "timer_record" / "2023-11.md"
        expected_history = (
            "# Timer Log — November 2023\n\n"
            "\n## 2023-11-14\n\n"
            "| Started | Project | Duration | Mode |\n"
            "|---------|---------|----------|------|\n"
            f"<!-- cloudyy-timer-completion:{timer['id']} -->\n"
            "| 22:13 | Tea - focus | 1m 30s | countdown (1m 30s) |\n"
        )
        self.assertEqual(history.read_text(encoding="utf-8"), expected_history)

        self.env["FAKE_NOTIFY_EXIT"] = "0"
        completed = self._json_timer("complete", timer["id"], "--json")
        repeated = self._json_timer("complete", timer["id"], "--json")

        self.assertEqual(completed, repeated)
        self.assertEqual(completed["state"], "completed")
        self.assertEqual(completed["elapsed_seconds"], 90)
        self.assertEqual(completed["remaining_seconds"], 0)
        state_file = self.state_home / "cloudyy" / "timers" / "state.json"
        tombstone = json.loads(state_file.read_text(encoding="utf-8"))["timers"][0]
        self.assertEqual(tombstone["completed_at"], 1700000000)
        self.assertTrue(tombstone["history_logged"])
        self.assertTrue(tombstone["completion_notified"])
        self.assertEqual(history.read_text(encoding="utf-8"), expected_history)
        self.assertEqual(
            self.notify_log.read_text(encoding="utf-8").splitlines(),
            [
                "--app-name=Cloudyy", "--urgency=normal", "Timer complete",
                "Tea | focus",
            ] * 2,
        )

    def test_list_automatically_retries_incomplete_completion_side_effects(self):
        timer = self._json_timer("create", "--label", "Tea", "--duration", "90")
        self.env["FAKE_NOTIFY_EXIT"] = "1"
        self.assertEqual(self._run("complete", timer["id"]).returncode, 8)
        self.env["FAKE_NOTIFY_EXIT"] = "0"

        listed = self._run("list", "--json")

        self.assertEqual(listed.returncode, 0, listed.stderr)
        state = json.loads(self._state_file().read_text(encoding="utf-8"))["timers"][0]
        self.assertTrue(state["history_logged"])
        self.assertTrue(state["completion_notified"])
        history = self.home / "Desktop" / "timer_record" / "2023-11.md"
        self.assertEqual(history.read_text(encoding="utf-8").count("| 22:13 | Tea |"), 1)

    def test_overdue_running_countdown_reconciles_to_one_completion(self):
        timer = self._json_timer("create", "--label", "Tea", "--duration", "90")
        self._set_now(1700000100)

        first = self._json_timer("list", "--json")
        second = self._json_timer("list", "--json")

        self.assertEqual(first["timers"][0]["state"], "completed")
        self.assertEqual(second, first)
        history = self.home / "Desktop" / "timer_record" / "2023-11.md"
        self.assertEqual(history.read_text(encoding="utf-8").count("| 22:15 | Tea |"), 1)
        self.assertEqual(
            self.notify_log.read_text(encoding="utf-8").splitlines(),
            ["--app-name=Cloudyy", "--urgency=normal", "Timer complete", "Tea"],
        )

    def test_history_marker_prevents_duplicate_row_after_ack_write_failure(self):
        timer = self._json_timer("create", "--label", "Tea", "--duration", "90")
        self.env["CLOUDYY_TIMER_FAIL_STATE_WRITE_AT"] = "2"

        first = self._run("complete", timer["id"])

        self.assertEqual(first.returncode, 6, first.stderr)
        self.env.pop("CLOUDYY_TIMER_FAIL_STATE_WRITE_AT")
        self.assertEqual(self._run("complete", timer["id"]).returncode, 0)
        history = self.home / "Desktop" / "timer_record" / "2023-11.md"
        self.assertEqual(history.read_text(encoding="utf-8").count("| 22:13 | Tea |"), 1)

    def test_semantically_invalid_state_is_rejected_byte_for_byte(self):
        valid = {
            "version": 1,
            "updated_at": 1700000000,
            "timers": [{
                "id": "ct-valid", "label": "Tea", "mode": "countdown",
                "state": "running", "duration_seconds": 90,
                "accumulated_seconds": 0, "paused_remaining_seconds": 90,
                "created_at": 1700000000, "transitioned_at": 1700000000,
                "deadline_at": 1700000090,
            }],
        }
        mutations = {
            "empty id": lambda d: d["timers"][0].update(id=""),
            "empty label": lambda d: d["timers"][0].update(label=""),
            "bad mode": lambda d: d["timers"][0].update(mode="alarm"),
            "bad state": lambda d: d["timers"][0].update(state="stopped"),
            "fractional duration": lambda d: d["timers"][0].update(duration_seconds=1.5),
            "negative accumulated": lambda d: d["timers"][0].update(accumulated_seconds=-1),
            "remaining beyond duration": lambda d: d["timers"][0].update(paused_remaining_seconds=91),
            "running null deadline": lambda d: d["timers"][0].update(deadline_at=None),
            "derived field persisted": lambda d: d["timers"][0].update(elapsed_seconds=0),
            "completed missing flags": lambda d: d["timers"][0].update(
                state="completed", deadline_at=None, paused_remaining_seconds=0,
                completed_at=1700000000,
            ),
            "partial provenance": lambda d: d["timers"][0].update(migration_source="legacy"),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                document = json.loads(json.dumps(valid))
                mutate(document)
                state_bytes = self._write_state(document)

                result = self._run("list", "--json")

                self.assertEqual(result.returncode, 5, result.stderr)
                self.assertEqual(self._state_file().read_bytes(), state_bytes)

    def test_concurrent_complete_emits_one_history_row_and_notification(self):
        timer = self._json_timer(
            "create", "--label", "Tea", "--duration", "90", "--json"
        )
        command = [TIMER, "complete", timer["id"], "--json"]

        processes = [
            subprocess.Popen(
                command,
                env=self.env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            for _ in range(2)
        ]
        results = [process.communicate(timeout=5) for process in processes]

        self.assertEqual([process.returncode for process in processes], [0, 0], results)
        history = self.home / "Desktop" / "timer_record" / "2023-11.md"
        self.assertEqual(history.read_text(encoding="utf-8").count("| 22:13 | Tea |"), 1)
        self.assertEqual(
            self.notify_log.read_text(encoding="utf-8").splitlines(),
            ["--app-name=Cloudyy", "--urgency=normal", "Timer complete", "Tea"],
        )

    def test_migration_marks_missing_source_once(self):
        result = self._run("list", "--json")

        self.assertEqual(result.returncode, 0, result.stderr)
        source = self.data_home / "quickshell" / "timer" / "active.json"
        self.assertEqual(
            self._migration_marker(),
            {
                "version": 1,
                "migrated_at": 1700000000,
                "source": str(source),
                "source_sha256": None,
                "status": "no-source",
                "imported": 0,
                "completed": 0,
                "skipped": 0,
            },
        )

    def test_migration_imports_legacy_modes_and_completes_expired_countdown(self):
        source, source_bytes = self._write_legacy({
            "version": 1,
            "savedAt": 1699999970,
            "timers": [
                {
                    "timerId": "paused-countdown", "label": "Paused",
                    "mode": "countdown", "targetSeconds": 90,
                    "elapsedSeconds": 20, "timerState": "paused",
                },
                {
                    "timerId": "live-countdown", "label": "Live",
                    "mode": "countdown", "targetSeconds": 90,
                    "elapsedSeconds": 20, "timerState": "running",
                },
                {
                    "timerId": "expired-countdown", "label": "Expired",
                    "mode": "countdown", "targetSeconds": 40,
                    "elapsedSeconds": 20, "timerState": "running",
                },
                {
                    "timerId": "running-stopwatch", "label": "Running",
                    "mode": "stopwatch", "targetSeconds": 0,
                    "elapsedSeconds": 10, "timerState": "running",
                },
                {
                    "timerId": "paused-stopwatch", "label": "Paused watch",
                    "mode": "stopwatch", "targetSeconds": 0,
                    "elapsedSeconds": 15, "timerState": "paused",
                },
                {"timerId": "broken", "mode": "countdown"},
            ],
        })

        result = self._run("list", "--json")

        self.assertEqual(result.returncode, 0, result.stderr)
        timers = {timer["id"]: timer for timer in json.loads(result.stdout)["timers"]}
        self.assertEqual(set(timers), {
            "paused-countdown", "live-countdown", "expired-countdown",
            "running-stopwatch", "paused-stopwatch",
        })
        self.assertEqual(timers["paused-countdown"]["remaining_seconds"], 70)
        self.assertEqual(timers["paused-countdown"]["state"], "paused")
        self.assertEqual(timers["live-countdown"]["remaining_seconds"], 40)
        self.assertEqual(timers["live-countdown"]["deadline_at"], 1700000040)
        self.assertEqual(timers["expired-countdown"]["state"], "completed")
        self.assertEqual(timers["expired-countdown"]["remaining_seconds"], 0)
        self.assertEqual(timers["running-stopwatch"]["elapsed_seconds"], 40)
        self.assertEqual(timers["paused-stopwatch"]["elapsed_seconds"], 15)
        self.assertIn("--on-calendar=@1700000040", self.systemd_run_log.read_text(encoding="utf-8"))
        self.assertEqual(
            self.notify_log.read_text(encoding="utf-8").splitlines(),
            ["--app-name=Cloudyy", "--urgency=normal", "Timer complete", "Expired"],
        )
        marker = self._migration_marker()
        self.assertEqual(marker["status"], "migrated")
        self.assertEqual(marker["imported"], 4)
        self.assertEqual(marker["completed"], 1)
        self.assertEqual(marker["skipped"], 1)
        self.assertEqual(marker["source_sha256"], hashlib.sha256(source_bytes).hexdigest())
        self.assertEqual(source.read_bytes(), source_bytes)

    def test_migration_rejects_malformed_document_without_marker_or_rewrite(self):
        source = self.data_home / "quickshell" / "timer" / "active.json"
        source.parent.mkdir(parents=True)
        source_bytes = b'{"version":1,"timers":[broken]\n'
        source.write_bytes(source_bytes)

        result = self._run("list", "--json")

        self.assertEqual(result.returncode, 9, result.stderr)
        self.assertEqual(source.read_bytes(), source_bytes)
        self.assertFalse(
            (self.state_home / "cloudyy" / "timers" / "migration-v1.json").exists()
        )
        state = json.loads(
            (self.state_home / "cloudyy" / "timers" / "state.json").read_text()
        )
        self.assertEqual(state["timers"], [])

    def test_migration_appends_to_provider_state_and_skips_id_collisions(self):
        state_dir = self.state_home / "cloudyy" / "timers"
        state_dir.mkdir(parents=True)
        (state_dir / "state.json").write_text(json.dumps({
            "version": 1,
            "updated_at": 1699999900,
            "timers": [{
                "id": "existing", "label": "Provider", "mode": "stopwatch",
                "state": "paused", "duration_seconds": None,
                "accumulated_seconds": 12, "paused_remaining_seconds": None,
                "created_at": 1699999800, "transitioned_at": 1699999900,
                "deadline_at": None,
            }],
        }), encoding="utf-8")
        self._write_legacy({
            "version": 1,
            "savedAt": 1699999990,
            "timers": [
                {
                    "timerId": "existing", "label": "Legacy collision",
                    "mode": "stopwatch", "targetSeconds": 0,
                    "elapsedSeconds": 3, "timerState": "paused",
                },
                {
                    "timerId": "legacy-new", "label": "Legacy new",
                    "mode": "stopwatch", "targetSeconds": 0,
                    "elapsedSeconds": 7, "timerState": "paused",
                },
            ],
        })

        timers = self._listed_timers()

        self.assertEqual([timer["id"] for timer in timers], ["existing", "legacy-new"])
        self.assertEqual(timers[0]["label"], "Provider")
        self.assertEqual(self._migration_marker()["imported"], 1)
        self.assertEqual(self._migration_marker()["skipped"], 1)

    def test_migration_marker_prevents_duplicate_import(self):
        state_dir = self.state_home / "cloudyy" / "timers"
        state_dir.mkdir(parents=True)
        marker = state_dir / "migration-v1.json"
        marker_bytes = b'{"version":1,"status":"already-migrated"}\n'
        marker.write_bytes(marker_bytes)
        source, source_bytes = self._write_legacy({
            "version": 1,
            "savedAt": 1699999990,
            "timers": [{
                "timerId": "ignored", "label": "Ignored", "mode": "countdown",
                "targetSeconds": 60, "elapsedSeconds": 0, "timerState": "running",
            }],
        })

        self.assertEqual(self._listed_timers(), [])
        self.assertEqual(marker.read_bytes(), marker_bytes)
        self.assertEqual(source.read_bytes(), source_bytes)
        self.assertFalse(self.systemd_run_log.exists())

    def test_migration_schedule_failure_leaves_state_unimported_and_marker_absent(self):
        source, source_bytes = self._write_legacy({
            "version": 1,
            "savedAt": 1699999990,
            "timers": [{
                "timerId": "live", "label": "Live", "mode": "countdown",
                "targetSeconds": 60, "elapsedSeconds": 0, "timerState": "running",
            }],
        })
        self.env["FAKE_SYSTEMD_RUN_EXIT"] = "1"

        result = self._run("list", "--json")

        self.assertEqual(result.returncode, 9, result.stderr)
        state = json.loads(
            (self.state_home / "cloudyy" / "timers" / "state.json").read_text()
        )
        self.assertEqual(state["timers"], [])
        self.assertFalse(
            (self.state_home / "cloudyy" / "timers" / "migration-v1.json").exists()
        )
        self.assertEqual(source.read_bytes(), source_bytes)

    def test_migration_retries_failed_expired_notification_before_marking_complete(self):
        source, source_bytes = self._write_legacy({
            "version": 1,
            "savedAt": 1699999900,
            "timers": [{
                "timerId": "expired", "label": "Expired", "mode": "countdown",
                "targetSeconds": 60, "elapsedSeconds": 0, "timerState": "running",
            }],
        })
        self.env["FAKE_NOTIFY_EXIT"] = "1"

        first = self._run("list", "--json")

        self.assertEqual(first.returncode, 9, first.stderr)
        marker = self.state_home / "cloudyy" / "timers" / "migration-v1.json"
        self.assertFalse(marker.exists())
        self.env["FAKE_NOTIFY_EXIT"] = "0"

        timers = self._listed_timers()

        self.assertEqual(len(timers), 1)
        self.assertEqual(timers[0]["id"], "expired")
        self.assertEqual(timers[0]["state"], "completed")
        self.assertEqual(self._migration_marker()["completed"], 1)
        self.assertEqual(
            self.notify_log.read_text(encoding="utf-8").splitlines(),
            ["--app-name=Cloudyy", "--urgency=normal", "Timer complete", "Expired"] * 2,
        )
        history = self.home / "Desktop" / "timer_record" / "2023-11.md"
        self.assertEqual(history.read_text(encoding="utf-8").count("| Expired |"), 1)
        self.assertEqual(source.read_bytes(), source_bytes)

    def test_reconciliation_retries_preexisting_incomplete_completion_after_migration(self):
        state_dir = self.state_home / "cloudyy" / "timers"
        state_dir.mkdir(parents=True)
        (state_dir / "state.json").write_text(json.dumps({
            "version": 1,
            "updated_at": 1699999990,
            "timers": [{
                "id": "collision", "label": "Provider completion",
                "mode": "countdown", "state": "completed",
                "duration_seconds": 60, "accumulated_seconds": 0,
                "paused_remaining_seconds": 0, "created_at": 1699999800,
                "transitioned_at": 1699999900, "deadline_at": None,
                "completed_at": 1699999900, "history_logged": False,
                "completion_notified": False,
            }],
        }), encoding="utf-8")
        source, source_bytes = self._write_legacy({
            "version": 1,
            "savedAt": 1699999900,
            "timers": [{
                "timerId": "collision", "label": "Legacy completion",
                "mode": "countdown", "targetSeconds": 60,
                "elapsedSeconds": 0, "timerState": "running",
            }],
        })

        timers = self._listed_timers()

        self.assertEqual(len(timers), 1)
        self.assertEqual(timers[0]["label"], "Provider completion")
        self.assertEqual(self._migration_marker()["completed"], 0)
        self.assertEqual(self._migration_marker()["skipped"], 1)
        self.assertEqual(
            self.notify_log.read_text(encoding="utf-8").splitlines(),
            ["--app-name=Cloudyy", "--urgency=normal", "Timer complete",
             "Provider completion"],
        )
        history = self.home / "Desktop" / "timer_record" / "2023-11.md"
        self.assertEqual(history.read_text(encoding="utf-8").count("| Provider completion |"), 1)
        self.assertEqual(source.read_bytes(), source_bytes)

    def test_migration_state_write_failure_cancels_schedules_and_imports_nothing(self):
        source, source_bytes = self._write_legacy({
            "version": 1,
            "savedAt": 1699999990,
            "timers": [{
                "timerId": "scheduled", "label": "Scheduled",
                "mode": "countdown", "targetSeconds": 60,
                "elapsedSeconds": 0, "timerState": "running",
            }],
        })
        self.env["CLOUDYY_TIMER_FAIL_MIGRATION_STATE_WRITE"] = "1"

        result = self._run("list", "--json")

        self.assertEqual(result.returncode, 9, result.stderr)
        state = json.loads(
            (self.state_home / "cloudyy" / "timers" / "state.json").read_text()
        )
        self.assertEqual(state["timers"], [])
        self.assertFalse(
            (self.state_home / "cloudyy" / "timers" / "migration-v1.json").exists()
        )
        self.assertEqual(
            self.systemctl_log.read_text(encoding="utf-8").splitlines(),
            [
                "--user", "stop", "cloudyy-timer-scheduled.timer",
                "cloudyy-timer-scheduled.service",
            ],
        )
        self.assertEqual(source.read_bytes(), source_bytes)

    def test_migration_marker_write_retry_reconstructs_original_counts(self):
        source, source_bytes = self._write_legacy({
            "version": 1,
            "savedAt": 1699999900,
            "timers": [
                {
                    "timerId": "paused", "label": "Paused", "mode": "stopwatch",
                    "targetSeconds": 0, "elapsedSeconds": 12,
                    "timerState": "paused",
                },
                {
                    "timerId": "expired", "label": "Expired", "mode": "countdown",
                    "targetSeconds": 60, "elapsedSeconds": 0,
                    "timerState": "running",
                },
                {"timerId": "broken", "mode": "countdown"},
            ],
        })
        source_hash = hashlib.sha256(source_bytes).hexdigest()
        self.env["CLOUDYY_TIMER_FAIL_MIGRATION_MARKER_WRITE"] = "1"

        first = self._run("list", "--json")

        self.assertEqual(first.returncode, 9, first.stderr)
        marker = self.state_home / "cloudyy" / "timers" / "migration-v1.json"
        self.assertFalse(marker.exists())
        state_file = self.state_home / "cloudyy" / "timers" / "state.json"
        persisted = json.loads(state_file.read_text(encoding="utf-8"))["timers"]
        self.assertEqual(len(persisted), 2)
        for timer in persisted:
            self.assertEqual(timer["migration_source"], str(source))
            self.assertEqual(timer["migration_source_sha256"], source_hash)
        self.env.pop("CLOUDYY_TIMER_FAIL_MIGRATION_MARKER_WRITE")

        timers = self._listed_timers()

        self.assertEqual({timer["id"] for timer in timers}, {"paused", "expired"})
        self.assertEqual(
            self._migration_marker(),
            {
                "version": 1,
                "migrated_at": 1700000000,
                "source": str(source),
                "source_sha256": source_hash,
                "status": "migrated",
                "imported": 1,
                "completed": 1,
                "skipped": 1,
            },
        )
        self.assertEqual(
            self.notify_log.read_text(encoding="utf-8").splitlines(),
            ["--app-name=Cloudyy", "--urgency=normal", "Timer complete", "Expired"],
        )
        history = self.home / "Desktop" / "timer_record" / "2023-11.md"
        self.assertEqual(history.read_text(encoding="utf-8").count("| Expired |"), 1)
        self.assertEqual(source.read_bytes(), source_bytes)


if __name__ == "__main__":
    unittest.main()
