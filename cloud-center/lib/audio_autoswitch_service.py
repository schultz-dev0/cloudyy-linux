"""Persistent pactl subscription runner for automatic output selection."""
from __future__ import annotations

import logging
import signal
import subprocess
import threading
import time
from typing import Any, Callable

from lib import audio_core


log = logging.getLogger(__name__)
DEBOUNCE_SECONDS = 0.5
SHUTDOWN_TIMEOUT_SECONDS = 2


class AudioAutoSwitchRunner:
    """Evaluate the shared selection policy for debounced sink events."""

    def __init__(
        self,
        *,
        policy: audio_core.AutoSwitchPolicy | None = None,
        config_loader: Callable[[], dict[str, Any]] = audio_core.load_auto_switch_config,
        sink_loader: Callable[[], list[audio_core.Sink]] = audio_core.list_sinks,
        default_loader: Callable[[], str] = lambda: audio_core.get_default("sink"),
        switcher: Callable[[str], tuple[bool, str]] = audio_core.switch_output,
        popen: Any = subprocess.Popen,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.policy = policy or audio_core.AutoSwitchPolicy()
        self.config_loader = config_loader
        self.sink_loader = sink_loader
        self.default_loader = default_loader
        self.switcher = switcher
        self.popen = popen
        self.clock = clock
        self.stop_event = threading.Event()
        self.process: Any = None
        self.last_evaluation = 0.0

    def evaluate(self) -> None:
        """Reread configuration and select a sink when the policy requests one."""
        config = self.config_loader()
        target = self.policy.choose(
            self.sink_loader(), self.default_loader(), config, self.clock(),
        )
        if not target:
            return
        ok, message = self.switcher(target)
        if not ok:
            log.warning("Automatic output switch failed: %s", message)

    def handle_event(self, line: str) -> None:
        """Evaluate only sink events, coalescing bursts into one evaluation."""
        if "on sink" not in line:
            return
        now = self.clock()
        if now - self.last_evaluation < DEBOUNCE_SECONDS:
            return
        self.last_evaluation = now
        self.evaluate()

    def run(self) -> None:
        """Own one pactl subscription process until stopped or it exits."""
        self.process = self.popen(
            ["pactl", "subscribe"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        assert self.process.stdout is not None
        for line in self.process.stdout:
            if self.stop_event.is_set():
                break
            self.handle_event(line)

    def stop(self) -> None:
        """Request a clean shutdown and terminate the owned child if needed."""
        self.stop_event.set()
        if self.process is None or self.process.poll() is not None:
            return
        try:
            self.process.terminate()
            self.process.wait(timeout=SHUTDOWN_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            try:
                self.process.kill()
                self.process.wait(timeout=SHUTDOWN_TIMEOUT_SECONDS)
            except subprocess.TimeoutExpired:
                log.warning("Timed out reaping pactl subscribe after kill")
            except ProcessLookupError:
                pass
        except ProcessLookupError:
            pass


def main() -> int:
    """Run under systemd and return failure when pactl cannot be started."""
    runner = AudioAutoSwitchRunner()

    def stop(_signum: int, _frame: Any) -> None:
        runner.stop()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        runner.run()
    except (FileNotFoundError, OSError, subprocess.SubprocessError) as exc:
        log.error("Failed to start pactl subscribe: %s", exc)
        return 1
    finally:
        runner.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
