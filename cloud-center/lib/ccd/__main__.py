"""
Cloud Center — lib/ccd/__main__.py
Sidecar entrypoint: python3 -m lib.ccd

Reads JSON-line requests on stdin, writes responses and events on stdout,
logs to stderr. Exits when stdin closes (the parent window died), stopping
every watcher and child process it started.
"""
from __future__ import annotations

import logging
import sys

# Importing these modules registers their methods in protocol.METHODS.
from lib.ccd import (  # noqa: F401
    actions,
    audio,
    battery,
    bluetooth,
    cursor,
    island_integrations,
    keybinds,
    model,
    monitors,
    online_wallpapers,
    protocol,
    recording,
    region,
    rules_startup,
    state,
    watchers,
    wifi,
    zsh_plugins,
    bezier,
)

logging.basicConfig(
    level=logging.INFO,
    format="[%(levelname)s] %(name)s: %(message)s",
    stream=sys.stderr,
)


def main() -> None:
    # Load config.yaml up front so subscribe works even before any get_model.
    model.load_model()
    try:
        for line in sys.stdin:
            reply = protocol.handle_line(line)
            if reply is not None:
                protocol.write_line(reply)
    finally:
        audio.shutdown()
        battery.shutdown()
        bluetooth.shutdown()
        cursor.shutdown()
        monitors.shutdown()
        recording.shutdown()
        region.shutdown()
        rules_startup.shutdown()
        state.shutdown()
        wifi.shutdown()


if __name__ == "__main__":
    main()
