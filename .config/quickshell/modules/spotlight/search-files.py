#!/usr/bin/env python3
"""Stream live fd results as JSON, preserving arbitrary filenames."""
from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
from pathlib import Path


def search(query: str) -> None:
    limit = max(1, int(os.environ.get("MAX_FILE_RESULTS", "10")))
    # Keep developer dependency/build trees out of interactive traversal.
    excludes = ("node_modules", ".git", "__pycache__", ".venv", "venv", ".cache")
    base = ["fd", "--hidden", "--no-ignore-vcs", "--ignore-case", "--fixed-strings", "--print0",
            "--max-results", str(limit)]
    for name in excludes:
        base.extend(["--exclude", name])
    patterns = [query]
    if re.search(r"[a-z][A-Z]", query):
        patterns += [part for part in re.sub(r"([a-z])([A-Z])", r"\1 \2", query).split() if len(part) >= 3]
    seen = set()
    for pattern in patterns:
        with subprocess.Popen([*base, "--", pattern, str(Path.home())], stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL) as proc:
            try:
                buffer = b""
                while chunk := os.read(proc.stdout.fileno(), 65536):
                    buffer += chunk
                    paths = buffer.split(b"\0")
                    buffer = paths.pop()
                    for raw in paths:
                        path = os.fsdecode(raw)
                        if path in seen:
                            continue
                        seen.add(path)
                        print(json.dumps({"type": "file", "name": Path(path).name, "path": path}), flush=True)
                        if len(seen) >= limit:
                            return
            finally:
                if proc.poll() is None:
                    proc.terminate()


if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1]:
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    search(sys.argv[1])
