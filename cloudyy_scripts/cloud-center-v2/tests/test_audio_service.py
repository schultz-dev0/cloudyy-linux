import io
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib import audio_core


class AudioServiceControlTests(unittest.TestCase):
    def test_policy_enabled_when_bluetooth_default_is_active(self):
        from lib.audio_service_control import policy_enabled

        self.assertTrue(policy_enabled(dict(audio_core.AUTO_SWITCH_DEFAULTS)))

    def test_policy_disabled_only_when_both_policies_are_off(self):
        from lib.audio_service_control import policy_enabled

        self.assertFalse(policy_enabled({"bluetooth_auto_switch": False, "enabled": False}))

    def test_migration_prompt_requires_active_policy_and_inactive_service(self):
        from lib.audio_service_control import should_prompt_migration

        config = dict(audio_core.AUTO_SWITCH_DEFAULTS)
        self.assertTrue(should_prompt_migration(
            config, {"present": True, "enabled": False, "active": False},
        ))
        config["service_prompt_version"] = 1
        self.assertFalse(should_prompt_migration(
            config, {"present": True, "enabled": False, "active": False},
        ))

    def test_enable_reloads_then_enables_user_unit(self):
        from lib import audio_service_control

        completed = mock.Mock(returncode=0, stdout="", stderr="")
        runner = mock.Mock(return_value=completed)

        result = audio_service_control.set_service_enabled(
            True, reload_daemon=True, run=runner,
        )

        self.assertTrue(result["ok"])
        self.assertEqual(runner.call_args_list[0].args[0][-1], "daemon-reload")
        self.assertEqual(
            runner.call_args_list[1].args[0][-3:],
            ["enable", "--now", audio_service_control.SERVICE_NAME],
        )

    def test_service_status_handles_missing_unit_without_systemctl(self):
        from lib.audio_service_control import service_status

        with TemporaryDirectory() as temporary:
            result = service_status(
                run=mock.Mock(), unit_path=Path(temporary) / "missing.service",
            )

        self.assertEqual(
            result,
            {"present": False, "loaded": False, "enabled": False,
             "active": False, "error": "Service unit is not installed"},
        )

    def test_dismiss_prompt_returns_versioned_copy(self):
        from lib.audio_service_control import SERVICE_PROMPT_VERSION, dismiss_service_prompt

        config = dict(audio_core.AUTO_SWITCH_DEFAULTS)
        result = dismiss_service_prompt(config)

        self.assertNotIn("service_prompt_version", config)
        self.assertEqual(result["service_prompt_version"], SERVICE_PROMPT_VERSION)


class AudioAutoSwitchRunnerTests(unittest.TestCase):
    def test_evaluate_rereads_config_and_switches_selected_sink(self):
        from lib.audio_autoswitch_service import AudioAutoSwitchRunner

        sink = audio_core.Sink(
            1, "bluez_output.one.a2dp", "Headphones", 50, False, False, "",
            state="RUNNING",
        )
        policy = mock.Mock()
        policy.choose.return_value = sink.name
        config_loader = mock.Mock(return_value={"bluetooth_auto_switch": True})
        switch = mock.Mock(return_value=(True, ""))
        runner = AudioAutoSwitchRunner(
            policy=policy,
            config_loader=config_loader,
            sink_loader=mock.Mock(return_value=[sink]),
            default_loader=mock.Mock(return_value="sink.old"),
            switcher=switch,
        )

        runner.evaluate()

        config_loader.assert_called_once_with()
        switch.assert_called_once_with(sink.name)

    def test_non_sink_events_do_not_evaluate(self):
        from lib.audio_autoswitch_service import AudioAutoSwitchRunner

        runner = AudioAutoSwitchRunner()
        runner.evaluate = mock.Mock()

        runner.handle_event("Event 'change' on source #2")

        runner.evaluate.assert_not_called()

    def test_sink_events_are_debounced(self):
        from lib.audio_autoswitch_service import AudioAutoSwitchRunner

        clock = mock.Mock(side_effect=[1.0, 1.2, 1.6])
        runner = AudioAutoSwitchRunner(clock=clock)
        runner.evaluate = mock.Mock()

        runner.handle_event("Event 'change' on sink #2")
        runner.handle_event("Event 'change' on sink #2")
        runner.handle_event("Event 'change' on sink #2")

        self.assertEqual(runner.evaluate.call_count, 2)

    def test_run_raises_when_subscription_startup_fails(self):
        from lib.audio_autoswitch_service import AudioAutoSwitchRunner

        runner = AudioAutoSwitchRunner(
            popen=mock.Mock(side_effect=FileNotFoundError("pactl")),
        )

        with self.assertRaises(FileNotFoundError):
            runner.run()

    def test_run_owns_one_subscription_process_and_stops_it(self):
        from lib.audio_autoswitch_service import AudioAutoSwitchRunner

        process = mock.Mock(stdout=io.StringIO("Event 'change' on source #2\n"))
        process.poll.return_value = None
        runner = AudioAutoSwitchRunner(popen=mock.Mock(return_value=process))

        runner.run()
        runner.stop()

        self.assertEqual(runner.popen.call_count, 1)
        process.terminate.assert_called_once_with()
        process.wait.assert_called_once_with(timeout=2)

    def test_stop_kills_and_reaps_child_after_terminate_timeout(self):
        from lib.audio_autoswitch_service import AudioAutoSwitchRunner

        process = mock.Mock()
        process.poll.return_value = None
        process.wait.side_effect = [
            subprocess.TimeoutExpired("pactl", 2),
            None,
        ]
        runner = AudioAutoSwitchRunner()
        runner.process = process

        runner.stop()

        process.terminate.assert_called_once_with()
        process.kill.assert_called_once_with()
        self.assertEqual(process.wait.call_args_list, [
            mock.call(timeout=2),
            mock.call(timeout=2),
        ])

    def test_stop_without_process_is_a_clean_noop(self):
        from lib.audio_autoswitch_service import AudioAutoSwitchRunner

        runner = AudioAutoSwitchRunner()

        runner.stop()

        self.assertTrue(runner.stop_event.is_set())

    def test_stop_does_not_touch_an_already_exited_process(self):
        from lib.audio_autoswitch_service import AudioAutoSwitchRunner

        process = mock.Mock()
        process.poll.return_value = 0
        runner = AudioAutoSwitchRunner()
        runner.process = process

        runner.stop()

        process.terminate.assert_not_called()
        process.wait.assert_not_called()
        process.kill.assert_not_called()


if __name__ == "__main__":
    unittest.main()
