"""CLI: print hyprcap / wf-recorder args from Cloud Center recording settings."""
from __future__ import annotations

import argparse
from typing import Any

from lib import recording_core


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Print shell-safe hyprcap/wf-recorder args from recording settings.",
    )
    parser.add_argument("--kind", choices=("shot", "rec"), default="rec")
    parser.add_argument("--filename")
    parser.add_argument("--ensure-audio", action="store_true")
    return parser.parse_args(argv)


def should_resolve_audio(
    settings: dict[str, Any],
    *,
    kind: str,
    ensure_audio: bool,
) -> bool:
    if kind != "rec":
        return False
    use_mic = bool(settings.get("rec_audio_mic"))
    use_desktop = bool(settings.get("rec_audio_desktop"))
    if ensure_audio:
        return use_mic or use_desktop
    return use_mic and use_desktop


def print_recording_args(
    *,
    kind: str = "rec",
    filename: str | None = None,
    ensure_audio: bool = False,
    settings: dict[str, Any] | None = None,
) -> str:
    settings = settings or recording_core.load_settings()
    audio_source = None
    if should_resolve_audio(settings, kind=kind, ensure_audio=ensure_audio):
        resolved = recording_core.resolve_audio_source(settings)
        if not resolved.get("ok"):
            raise SystemExit(resolved.get("message") or "Audio resolution failed")
        audio_source = resolved.get("source")
    return recording_core.format_recording_args_shell(
        settings,
        kind=kind,
        filename=filename,
        audio_source=audio_source,
    )


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    print(print_recording_args(
        kind=args.kind,
        filename=args.filename,
        ensure_audio=args.ensure_audio,
    ))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
