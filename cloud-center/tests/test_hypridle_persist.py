import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from lib import hypridle_persist


SAMPLE_CONFIG = """general {
    lock_cmd = cloudyy-lock
    before_sleep_cmd = cloudyy-lock
}

listener {
    timeout = 900
    on-timeout = cloudyy-idle show
    on-resume = cloudyy-idle dismiss
}

listener {
    timeout = 2700
    on-timeout = cloudyy-lock
}
"""


class HypridlePersistTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.config = Path(self.tmp.name) / "hypridle.conf"
        self.config.write_text(SAMPLE_CONFIG, encoding="utf-8")

        config_patch = mock.patch.object(hypridle_persist, "HYPRIDLE_CONF", self.config)
        config_patch.start()
        self.addCleanup(config_patch.stop)

    def test_apply_scene_updates_only_the_idle_scene_listener(self):
        seconds = hypridle_persist.apply("scene", "20", restart=False)

        self.assertEqual(seconds, 1200)
        source = self.config.read_text(encoding="utf-8")
        self.assertIn("timeout = 1200\n    on-timeout = cloudyy-idle show", source)
        self.assertIn("timeout = 2700\n    on-timeout = cloudyy-lock", source)

    def test_apply_lock_updates_only_the_lock_listener(self):
        seconds = hypridle_persist.apply("lock", "60", restart=False)

        self.assertEqual(seconds, 3600)
        source = self.config.read_text(encoding="utf-8")
        self.assertIn("timeout = 900\n    on-timeout = cloudyy-idle show", source)
        self.assertIn("timeout = 3600\n    on-timeout = cloudyy-lock", source)

    def test_scene_can_be_disabled_without_touching_the_lock_listener(self):
        enabled = hypridle_persist.set_scene_enabled(False, restart=False)

        self.assertIs(enabled, False)
        source = self.config.read_text(encoding="utf-8")
        self.assertIn("timeout = 900\n    on-timeout = true\n    on-resume = cloudyy-idle dismiss", source)
        self.assertIn("timeout = 2700\n    on-timeout = cloudyy-lock", source)

    def test_scene_can_be_reenabled_after_being_disabled(self):
        hypridle_persist.set_scene_enabled(False, restart=False)
        enabled = hypridle_persist.set_scene_enabled(True, restart=False)

        self.assertIs(enabled, True)
        source = self.config.read_text(encoding="utf-8")
        self.assertIn("timeout = 900\n    on-timeout = cloudyy-idle show", source)
        self.assertIn("timeout = 2700\n    on-timeout = cloudyy-lock", source)

    def test_scene_timeout_can_still_change_while_the_scene_is_disabled(self):
        hypridle_persist.set_scene_enabled(False, restart=False)
        hypridle_persist.apply("scene", "20", restart=False)

        source = self.config.read_text(encoding="utf-8")
        self.assertIn("timeout = 1200\n    on-timeout = true", source)
        self.assertIn("timeout = 2700\n    on-timeout = cloudyy-lock", source)

    def test_apply_restarts_hypridle_by_default(self):
        completed = subprocess.CompletedProcess(["systemctl"], 0, "", "")
        with mock.patch.object(hypridle_persist.subprocess, "run", return_value=completed) as run:
            hypridle_persist.apply("scene", "15")

        run.assert_called_once_with(
            ["systemctl", "--user", "restart", "hypridle.service"],
            capture_output=True,
            text=True,
            timeout=5,
        )

    def test_restart_failure_raises(self):
        completed = subprocess.CompletedProcess(["systemctl"], 1, "", "boom")
        with mock.patch.object(hypridle_persist.subprocess, "run", return_value=completed):
            with self.assertRaisesRegex(RuntimeError, "could not restart hypridle"):
                hypridle_persist.apply("scene", "15")

    def test_unknown_target_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "unsupported idle timeout target"):
            hypridle_persist.apply("display", "15", restart=False)

    def test_missing_target_listener_is_rejected(self):
        self.config.write_text("general {\n}\n", encoding="utf-8")

        with self.assertRaisesRegex(ValueError, "no hypridle listener found"):
            hypridle_persist.apply("scene", "15", restart=False)


if __name__ == "__main__":
    unittest.main()
