import time
import unittest
from unittest import mock

from lib.ccd import protocol, state, watchers

# Real lines captured from `bluetoothctl` on 2026-07-07 (ANSI codes included).
POWERED_NO = (
    "\x1b[0;94m[bluetoothctl]> \x1b[0m\x1b[K[\x1b[0;93mCHG\x1b[0m] "
    "Controller D4:54:8B:DC:28:81 Powered: no"
)
POWERED_YES = (
    "\x1b[0;94m[bluetoothctl]> \x1b[0m\x1b[K[\x1b[0;93mCHG\x1b[0m] "
    "Controller D4:54:8B:DC:28:81 Powered: yes"
)

BT_ITEM = {
    "type": "toggle",
    "properties": {
        "title": "Bluetooth",
        "key": "hypr/bluetooth",
        "state_command": "echo yes",
    },
}


def wait_for(condition, timeout=5.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return True
        time.sleep(0.02)
    return False


class TestParseBluetoothctlLine(unittest.TestCase):
    def test_powered_no(self):
        self.assertIs(watchers.parse_bluetoothctl_line(POWERED_NO), False)

    def test_powered_yes(self):
        self.assertIs(watchers.parse_bluetoothctl_line(POWERED_YES), True)

    def test_unrelated_lines_are_ignored(self):
        for line in ["Agent registered", "[CHG] Device AA Connected: yes", ""]:
            self.assertIsNone(watchers.parse_bluetoothctl_line(line), line)


class TestRegistry(unittest.TestCase):
    def test_bluetooth_key_is_registered(self):
        self.assertIn("hypr/bluetooth", state.KEY_WATCHER_FACTORIES)

    def test_state_engine_uses_the_factory(self):
        watcher = state.make_watcher("p/0/0", BT_ITEM)
        self.assertIsNotNone(watcher.run)  # stream watcher, not polling

    def test_missing_binary_falls_back_to_polling(self):
        with mock.patch.object(watchers.shutil, "which", return_value=None):
            watcher = watchers.make_bluetooth_watcher("p/0/0", BT_ITEM)
        self.assertIsNone(watcher.run)  # generic poll watcher


class TestStreamWatcher(unittest.TestCase):
    def setUp(self):
        self.events = []
        events_patch = mock.patch.object(
            protocol, "write_line", lambda payload: self.events.append(payload)
        )
        events_patch.start()
        self.addCleanup(events_patch.stop)

    def state_events(self):
        return [e for e in self.events if e.get("event") == "state"]

    def test_stream_lines_become_state_events(self):
        printf = "printf '%s\\n' 'Controller AA Powered: no'; sleep 30"
        watcher = watchers.make_stream_watcher(
            "p/0/0", BT_ITEM, ["bash", "-c", printf], watchers.parse_bluetoothctl_line
        )
        self.addCleanup(state.stop_watcher, watcher)
        state.start_watcher(watcher)

        # Initial check (state_command "echo yes") then the stream line.
        self.assertTrue(wait_for(lambda: len(self.state_events()) == 2))
        self.assertIs(self.state_events()[0]["value"], True)
        self.assertIs(self.state_events()[1]["value"], False)

    def test_stop_terminates_the_stream_process(self):
        watcher = watchers.make_stream_watcher(
            "p/0/0", BT_ITEM, ["bash", "-c", "sleep 300"], lambda line: None
        )
        state.start_watcher(watcher)
        self.assertTrue(wait_for(lambda: watcher.process is not None))

        state.stop_watcher(watcher)
        self.assertTrue(wait_for(lambda: watcher.process.poll() is not None))


if __name__ == "__main__":
    unittest.main()
