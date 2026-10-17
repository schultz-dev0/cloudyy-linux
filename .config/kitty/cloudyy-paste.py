"""Paste clipboard images as files, matching Kitty's drag-and-drop behavior."""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

from kittens.tui.handler import result_handler


def main(args: list[str]) -> None:
    pass


def _clipboard_image_path() -> str | None:
    types = subprocess.run(
        ["wl-paste", "--list-types"], capture_output=True, check=True, timeout=2,
    ).stdout.splitlines()
    if b"image/png" not in types:
        return None
    image = subprocess.run(
        ["wl-paste", "--no-newline", "--type", "image/png"],
        capture_output=True, check=True, timeout=3,
    ).stdout
    if not image.startswith(b"\x89PNG\r\n\x1a\n"):
        return None
    # Keep a separate copy: the screenshot shelf expires its temporary captures.
    directory = Path(os.environ.get("XDG_RUNTIME_DIR", tempfile.gettempdir())) / f"cloudyy-clipboard-{os.getuid()}"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = directory / f"image-{hashlib.sha256(image).hexdigest()}.png"
    if not path.exists():
        with tempfile.NamedTemporaryFile(dir=directory, delete=False) as handle:
            handle.write(image)
        os.replace(handle.name, path)
    return shlex.quote(str(path))


@result_handler(no_ui=True)
def handle_result(args: list[str], answer: str, target_window_id: int, boss) -> None:
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return
    try:
        path = _clipboard_image_path()
    except (OSError, subprocess.SubprocessError):
        path = None
    if path is None:
        boss.paste_from_clipboard()
    else:
        window.paste_text(path)
