import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from lib import lid_sleep_persist


class LidSleepPersistTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.unit_dir = Path(self.tmp.name) / "user"

        dir_patch = mock.patch.object(lid_sleep_persist, "UNIT_DIR", self.unit_dir)
        dir_patch.start()
        self.addCleanup(dir_patch.stop)

        completed = subprocess.CompletedProcess(["systemctl"], 0, "", "")
        run_patch = mock.patch.object(
            lid_sleep_persist.subprocess, "run", return_value=completed
        )
        self.run = run_patch.start()
        self.addCleanup(run_patch.stop)

    def _commands(self) -> list[list[str]]:
        return [call.args[0] for call in self.run.call_args_list]

    def test_disabling_sleep_writes_unit_and_enables_inhibitor(self):
        enabled = lid_sleep_persist.set_lid_sleep_enabled(False)

        self.assertIs(enabled, False)
        unit = self.unit_dir / lid_sleep_persist.UNIT_NAME
        self.assertTrue(unit.exists())
        self.assertIn("handle-lid-switch", unit.read_text(encoding="utf-8"))
        self.assertIn(["systemctl", "--user", "daemon-reload"], self._commands())
        self.assertIn(
            ["systemctl", "--user", "enable", "--now", lid_sleep_persist.UNIT_NAME],
            self._commands(),
        )

    def test_enabling_sleep_disables_inhibitor(self):
        enabled = lid_sleep_persist.set_lid_sleep_enabled(True)

        self.assertIs(enabled, True)
        self.assertIn(
            ["systemctl", "--user", "disable", "--now", lid_sleep_persist.UNIT_NAME],
            self._commands(),
        )

    def test_existing_unit_is_not_rewritten(self):
        unit = self.unit_dir / lid_sleep_persist.UNIT_NAME
        self.unit_dir.mkdir(parents=True)
        unit.write_text("custom\n", encoding="utf-8")

        lid_sleep_persist.set_lid_sleep_enabled(False)

        self.assertEqual(unit.read_text(encoding="utf-8"), "custom\n")
        self.assertNotIn(["systemctl", "--user", "daemon-reload"], self._commands())

    def test_systemctl_failure_raises(self):
        failed = subprocess.CompletedProcess(["systemctl"], 1, "", "boom")
        self.run.return_value = failed

        with self.assertRaisesRegex(RuntimeError, "systemctl --user"):
            lid_sleep_persist.set_lid_sleep_enabled(False)


if __name__ == "__main__":
    unittest.main()
