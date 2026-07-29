"""
Cloud Center — lib/ccd/protocol.py
JSON-lines protocol: request parsing, method dispatch, response/event output.

One JSON object per line. Requests carry "id" + "method" (+ optional "params");
responses echo the id. Events carry "event" instead of "id" and may be sent at
any time from any thread.
"""
from __future__ import annotations

import json
import logging
import sys
import threading
from typing import Any, Callable

log = logging.getLogger(__name__)

# The single dispatch table. Each ccd module registers its methods here at
# import time via register(); handle_line() looks them up by name.
METHODS: dict[str, Callable[[dict], Any]] = {}

# One lock guards stdout so responses and events never interleave mid-line.
STDOUT_LOCK = threading.Lock()


def register(name: str, handler: Callable[[dict], Any]) -> None:
    METHODS[name] = handler


def write_line(payload: dict) -> None:
    with STDOUT_LOCK:
        sys.stdout.write(json.dumps(payload) + "\n")
        sys.stdout.flush()


def send_event(payload: dict) -> None:
    """Push an unsolicited event to the frontend (thread-safe)."""
    write_line(payload)


def ok_response(request_id: Any, result: Any) -> dict:
    return {"id": request_id, "ok": True, "result": result}


def error_response(request_id: Any, message: str) -> dict:
    return {"id": request_id, "ok": False, "error": message}


def handle_line(line: str) -> dict | None:
    """Parse one request line and return the response dict (None for blanks)."""
    line = line.strip()
    if not line:
        return None

    try:
        request = json.loads(line)
    except json.JSONDecodeError as exc:
        return error_response(None, f"invalid JSON: {exc}")
    if not isinstance(request, dict):
        return error_response(None, "request must be a JSON object")

    request_id = request.get("id")
    method = request.get("method", "")
    handler = METHODS.get(method)
    if handler is None:
        return error_response(request_id, f"unknown method: {method}")

    try:
        return ok_response(request_id, handler(request.get("params") or {}))
    except Exception as exc:
        log.exception("method %s failed", method)
        return error_response(request_id, str(exc))


def ping(params: dict) -> str:
    return "pong"


register("ping", ping)
