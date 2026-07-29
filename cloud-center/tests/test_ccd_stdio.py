import json
import subprocess
import sys
import threading
import time
import unittest
from unittest import mock
from pathlib import Path

from lib.ccd import __main__ as ccd_main

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def wait_for(condition, timeout=10.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return True
        time.sleep(0.05)
    return False


def child_pids(pid: int) -> list[int]:
    children = Path(f"/proc/{pid}/task/{pid}/children")
    try:
        return [int(p) for p in children.read_text().split()]
    except (FileNotFoundError, ValueError):
        return []


def pid_alive(pid: int) -> bool:
    return Path(f"/proc/{pid}").exists()


class TestStdioEndToEnd(unittest.TestCase):
    def setUp(self):
        self.proc = subprocess.Popen(
            [sys.executable, "-m", "lib.ccd"],
            cwd=PROJECT_ROOT,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        self.lines = []
        self.reader = threading.Thread(target=self.read_stdout, daemon=True)
        self.reader.start()
        self.addCleanup(self.cleanup)

    def cleanup(self):
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()

    def read_stdout(self):
        for line in self.proc.stdout:
            self.lines.append(json.loads(line))

    def send(self, request: dict):
        self.proc.stdin.write(json.dumps(request) + "\n")
        self.proc.stdin.flush()

    def responses(self):
        return [l for l in self.lines if "id" in l]

    def events(self, kind: str):
        return [l for l in self.lines if l.get("event") == kind]

    def test_full_session_and_clean_exit(self):
        # subscribe works BEFORE any get_model call (model loads at startup)
        # and produces label events (CPU, memory, ...)
        self.send({"id": 1, "method": "subscribe", "params": {"page": "home"}})
        self.assertTrue(wait_for(lambda: self.responses()))
        self.assertGreater(self.responses()[0]["result"]["watchers"], 0)
        self.assertTrue(wait_for(lambda: self.events("label")))

        # get_model returns the real config.yaml model
        self.send({"id": 2, "method": "get_model"})
        self.assertTrue(wait_for(lambda: len(self.responses()) == 2))
        reply = self.responses()[1]
        self.assertTrue(reply["ok"])
        page_ids = [p["id"] for p in reply["result"]["pages"]]
        self.assertIn("home", page_ids)
        self.assertIn("__wifi__", page_ids)

        # closing stdin ends the process quickly and cleanly
        children = child_pids(self.proc.pid)
        self.proc.stdin.close()
        self.assertEqual(self.proc.wait(timeout=2), 0)

        # and nothing it spawned survives it
        self.assertTrue(
            wait_for(lambda: not any(pid_alive(pid) for pid in children), timeout=2),
            f"orphaned children: {[p for p in children if pid_alive(p)]}",
        )


class TestMainShutdown(unittest.TestCase):
    def test_stdin_close_discards_monitor_session(self):
        with mock.patch.object(ccd_main.model, "load_model"), \
             mock.patch.object(ccd_main.sys, "stdin", []), \
             mock.patch.object(ccd_main.state, "shutdown"), \
             mock.patch.object(ccd_main.rules_startup, "shutdown") as rules_shutdown, \
             mock.patch.object(ccd_main.monitors, "shutdown") as monitor_shutdown:
            ccd_main.main()
        monitor_shutdown.assert_called_once_with()
        rules_shutdown.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
