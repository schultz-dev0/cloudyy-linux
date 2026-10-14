#!/usr/bin/env python3
"""Watch catalog sources, including atomic replacements and newly created roots."""
from __future__ import annotations

import sys
from pathlib import Path

from gi.repository import Gio, GLib


def watch_paths(paths: list[Path], recursive: bool = False) -> None:
    roots = [path.absolute() for path in paths]
    monitors: dict[Path, Gio.FileMonitor] = {}
    pending = 0

    def relevant(path: Path) -> bool:
        return any(path == root or path in root.parents or root in path.parents for root in roots)

    def sync() -> None:
        wanted = set()
        for root in roots:
            parent = root.parent
            while not parent.is_dir() and parent != parent.parent:
                parent = parent.parent
            wanted.add(parent)
            if root.is_dir():
                wanted.add(root)
                if recursive:
                    wanted.update(path for path in root.rglob("*") if path.is_dir())
        for path in monitors.keys() - wanted:
            monitors.pop(path).cancel()
        for path in wanted - monitors.keys():
            try:
                monitor = Gio.File.new_for_path(str(path)).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
                monitor.connect("changed", changed)
                monitors[path] = monitor
            except GLib.Error as error:
                print(f"catalog watcher: {path}: {error}", file=sys.stderr)

    def notify() -> bool:
        nonlocal pending
        pending = 0
        sync()
        print("changed", flush=True)
        return GLib.SOURCE_REMOVE

    def changed(_monitor, file, other, _event) -> None:
        nonlocal pending
        if not any(item and item.get_path() and relevant(Path(item.get_path())) for item in (file, other)):
            return
        if pending:
            GLib.source_remove(pending)
        pending = GLib.timeout_add(120, notify)

    sync()
    # Reconcile once after watches are installed, closing the startup scan race.
    print("ready", flush=True)
    GLib.MainLoop().run()


if __name__ == "__main__":
    watch_paths([Path(arg) for arg in sys.argv[1:] if arg != "--recursive"], "--recursive" in sys.argv)
