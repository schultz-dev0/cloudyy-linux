#!/usr/bin/env python3
"""Fake ccd sidecar for frontend smoke tests: canned model, echoes actions."""
import json
import sys

MODEL = {
    "pages": [
        {"id": "home", "kind": "yaml", "title": "Home", "icon": "\U000f02dc",
         "sections": [{"title": "Demo", "items": [
             {"id": "home/0/0", "type": "toggle", "title": "Demo Toggle",
              "description": "does nothing", "icon": "\U000f0594", "key": "demo/x", "value": True},
             {"id": "home/0/1", "type": "label", "title": "CPU", "icon": "\U000f01c4", "text": "…"},
         ]}]},
        {"id": "__wifi__", "kind": "wifi", "title": "Wi-Fi",
         "icon": "\U000f0928"},
    ],
    "categories": [{"title": "Visuals", "pages": ["home"]},
                   {"title": "System", "pages": ["__wifi__"]}],
    "pinned": [{"id": "home", "title": "System Overview"}],
}


def reply(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


for line in sys.stdin:
    try:
        req = json.loads(line)
    except json.JSONDecodeError:
        continue
    method = req.get("method", "")
    if method == "get_model":
        reply({"id": req.get("id"), "ok": True, "result": MODEL})
    elif method == "subscribe":
        reply({"id": req.get("id"), "ok": True, "result": {"watchers": 1}})
        reply({"event": "label", "item": "home/0/1", "text": "FakeCPU 9000"})
    elif method == "run_action":
        reply({"id": req.get("id"), "ok": True, "result": {"started": True}})
        reply({"event": "action_done", "item": req["params"]["item"], "ok": True})
    else:
        reply({"id": req.get("id"), "ok": True, "result": None})
