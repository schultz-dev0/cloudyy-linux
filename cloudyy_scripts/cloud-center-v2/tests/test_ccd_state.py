import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import lib.utility as utility
from lib.ccd import actions, model, protocol, state

FIXTURE_YAML = """
pages:
  - id: home
    title: Home
    layout:
      - type: section
        properties: {title: Test}
        items:
          - type: toggle
            properties:
              title: Wifi
              key: test/wifi
              state_command: "cat {file}"
              interval: 0.05
            on_toggle:
              enabled: {command: "true"}
              disabled: {command: "true"}
          - type: toggle
            properties: {title: Plain, key: test/plain}
            on_toggle:
              enabled: {command: "true"}
              disabled: {command: "true"}
          - type: label
            properties: {title: CPU, interval: 0.05}
            value: {type: system, key: cpu}
          - type: label
            properties: {title: Motto}
            value: {type: static, text: hello}
          - type: label
            properties: {title: Uptime, interval: 0.05}
            value: {type: exec, command: "echo up"}
"""


def wait_for(condition, timeout=5.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return True
        time.sleep(0.02)
    return False


class StateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        tmp_path = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

        self.state_file = tmp_path / "state.txt"
        self.state_file.write_text("0")
        config_path = tmp_path / "config.yaml"
        config_path.write_text(FIXTURE_YAML.replace("{file}", str(self.state_file)))

        settings_patch = mock.patch.object(
            utility, "SETTINGS_DIR", tmp_path / "settings"
        )
        settings_patch.start()
        self.addCleanup(settings_patch.stop)

        model.load_model(config_path)

        self.events = []
        events_patch = mock.patch.object(
            protocol, "write_line", lambda payload: self.events.append(payload)
        )
        events_patch.start()
        self.addCleanup(events_patch.stop)

        self.addCleanup(state.shutdown)

    def state_events(self):
        return [e for e in self.events if e.get("event") == "state"]

    def label_events(self):
        return [e for e in self.events if e.get("event") == "label"]


class TestParseTruthy(unittest.TestCase):
    def test_truthy_words(self):
        for word in ["yes", "true", "1", "on", "enabled", "active", "running", "2"]:
            self.assertTrue(state.parse_truthy(word), word)

    def test_falsy_outputs(self):
        for word in ["no", "false", "0", "off", "garbage", ""]:
            self.assertFalse(state.parse_truthy(word), word)


class TestSubscribe(StateTest):
    def test_only_stateful_items_get_watchers(self):
        state.subscribe({"page": "home"})
        watched = {w.item_id for w in state.ACTIVE["home"]}
        # Wifi toggle (state_command) + three labels; not the plain toggle.
        self.assertEqual(
            watched, {"home/0/0", "home/0/2", "home/0/3", "home/0/4"}
        )

    def test_double_subscribe_does_not_duplicate(self):
        state.subscribe({"page": "home"})
        first = len(state.ACTIVE["home"])
        state.subscribe({"page": "home"})
        self.assertEqual(len(state.ACTIVE["home"]), first)

    def test_unsubscribe_stops_and_clears_watchers(self):
        state.subscribe({"page": "home"})
        watchers = list(state.ACTIVE["home"])
        state.unsubscribe({"page": "home"})
        self.assertNotIn("home", state.ACTIVE)
        self.assertTrue(
            wait_for(
                lambda: all(
                    w.thread is None or not w.thread.is_alive() for w in watchers
                )
            )
        )


class TestStateEvents(StateTest):
    def test_initial_state_is_reported_once(self):
        state.subscribe({"page": "home"})
        self.assertTrue(wait_for(lambda: self.state_events()))
        first = self.state_events()[0]
        self.assertEqual(first["item"], "home/0/0")
        self.assertEqual(first["key"], "test/wifi")
        self.assertIs(first["value"], False)

    def test_events_only_on_change(self):
        state.subscribe({"page": "home"})
        self.assertTrue(wait_for(lambda: len(self.state_events()) == 1))
        time.sleep(0.3)  # several poll cycles, no change
        self.assertEqual(len(self.state_events()), 1)

        self.state_file.write_text("1")
        self.assertTrue(wait_for(lambda: len(self.state_events()) == 2))
        self.assertIs(self.state_events()[1]["value"], True)

    def test_labels_emit_text(self):
        with mock.patch.object(utility, "get_system_info", return_value="TestCPU"):
            state.subscribe({"page": "home"})
            self.assertTrue(wait_for(lambda: len(self.label_events()) >= 3))
        by_item = {e["item"]: e["text"] for e in self.label_events()}
        self.assertEqual(by_item["home/0/2"], "TestCPU")
        self.assertEqual(by_item["home/0/3"], "hello")
        self.assertEqual(by_item["home/0/4"], "up")


class TestAfterActionRecheck(StateTest):
    def test_action_triggers_immediate_recheck(self):
        # Slow interval: only the recheck can produce the second event quickly.
        model.ITEMS["home/0/0"]["properties"]["interval"] = 60
        state.subscribe({"page": "home"})
        self.assertTrue(wait_for(lambda: len(self.state_events()) == 1))

        self.state_file.write_text("1")
        actions.run_action({"item": "home/0/0", "value": True})
        self.assertTrue(wait_for(lambda: len(self.state_events()) == 2, timeout=3))
        self.assertIs(self.state_events()[1]["value"], True)


if __name__ == "__main__":
    unittest.main()
