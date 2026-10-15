"""Cloud Center — lightweight bar output picker using the shared audio switcher."""
from __future__ import annotations

import json
import sys

from lib import audio_core


def run(args: list[str]) -> dict:
    if args == ["list"]:
        return {"ok": True, "outputs": [audio_core.serialize_device(sink) for sink in audio_core.list_sinks()]}
    if len(args) == 2 and args[0] == "switch":
        name = args[1]
        if not any(sink.name == name for sink in audio_core.list_sinks()):
            return {"ok": False, "error": "Audio output is no longer available"}
        ok, error = audio_core.switch_output(name)
        return {"ok": ok, "error": error or ("Could not switch audio output" if not ok else "")}
    raise ValueError("usage: audio_output_picker {list|switch <sink-name>}")


def main(args: list[str] | None = None) -> int:
    try:
        result = run(sys.argv[1:] if args is None else args)
    except Exception as error:
        result = {"ok": False, "error": str(error)}
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
