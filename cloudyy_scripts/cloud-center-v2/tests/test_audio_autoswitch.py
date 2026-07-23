import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib.audio_core import AutoSwitchPolicy, Sink


class TestPriorityAutoSwitch(unittest.TestCase):
    def test_priority_picker_ignores_suspended_sinks(self):
        policy = AutoSwitchPolicy()
        sinks = [
            Sink(
                index=1,
                name="alsa_output.usb-Corsair_CORSAIR_HS80_MAX_WIRELESS_Gaming_Receiver.analog-stereo",
                description="CORSAIR HS80 MAX WIRELESS Gaming Receiver Analog Stereo",
                volume=60,
                muted=False,
                is_default=False,
                active_port="analog-output",
                state="SUSPENDED",
            )
        ]

        self.assertIsNone(policy.pick_priority_sink(sinks, [sinks[0].name]))


if __name__ == "__main__":
    unittest.main()
