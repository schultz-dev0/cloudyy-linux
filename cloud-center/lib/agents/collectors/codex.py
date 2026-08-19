"""Collect Codex allowance windows from a short-lived app-server process."""
from __future__ import annotations

import json
from datetime import datetime, timezone


def _record(now: datetime, plan: str, allowances: list[dict], state: str) -> dict:
    timestamp = now.isoformat()
    messages = {"ok": "", "unavailable": "Usage unavailable", "error": "Collection failed"}
    return {
        "schemaVersion": 1,
        "recordId": "codex",
        "provider": {"id": "codex", "name": "Codex"},
        "planLabel": plan,
        "allowances": allowances,
        "dataUpdatedAt": timestamp,
        "lastAttemptAt": timestamp,
        "status": {"state": state, "message": messages[state]},
    }


def _allowance(window_id: str, label_prefix: str, value: object) -> dict | None:
    if not isinstance(value, dict):
        return None
    used_percent = value.get("usedPercent")
    if isinstance(used_percent, bool) or not isinstance(used_percent, (int, float)):
        return None
    if not 0 <= used_percent <= 100:
        return None
    duration = value.get("windowDurationMins")
    labels = {300: "5-hour session", 10080: "Weekly"}
    if duration not in labels:
        return None
    resets_at = value.get("resetsAt")
    if resets_at is None:
        reset_text = None
    elif isinstance(resets_at, (int, float)) and not isinstance(resets_at, bool):
        reset_text = datetime.fromtimestamp(resets_at, timezone.utc).isoformat()
    else:
        return None
    return {
        "id": window_id,
        "label": f"{label_prefix}{labels[duration]}",
        "usedPercent": used_percent,
        "resetAt": reset_text,
    }


def collect(now: datetime, runner, env: dict) -> dict:
    requests = [
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {"clientInfo": {"name": "cloudyy", "version": "1"}},
        },
        {"jsonrpc": "2.0", "method": "initialized", "params": {}},
        {"jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read", "params": {}},
    ]
    serialized = "".join(json.dumps(item, separators=(",", ":")) + "\n" for item in requests)
    try:
        completed = runner(
            ["codex", "app-server", "--listen", "stdio://"],
            input=serialized,
            text=True,
            capture_output=True,
            timeout=10,
            env=env,
        )
        if completed.returncode != 0:
            raise RuntimeError("app-server failed")
        response = None
        for line in completed.stdout.splitlines():
            candidate = json.loads(line)
            if isinstance(candidate, dict) and candidate.get("id") == 2:
                response = candidate
        if not isinstance(response, dict) or "error" in response:
            raise ValueError("missing rate-limit response")
        result = response.get("result")
        limits = result.get("rateLimits") if isinstance(result, dict) else None
        if not isinstance(limits, dict):
            return _record(now, "", [], "unavailable")

        allowances = []
        for key in ("primary", "secondary"):
            item = _allowance(key, "", limits.get(key))
            if item is not None:
                allowances.append(item)
        scoped = result.get("rateLimitsByLimitId")
        if isinstance(scoped, dict):
            for limit_id, limit in scoped.items():
                if not isinstance(limit_id, str) or not isinstance(limit, dict):
                    continue
                name = limit.get("limitName")
                if not isinstance(name, str) or not name.strip():
                    continue
                for key in ("primary", "secondary"):
                    item = _allowance(f"{limit_id}-{key}", f"{name} ", limit.get(key))
                    if item is not None:
                        allowances.append(item)
        if not allowances:
            return _record(now, "", [], "unavailable")
    except Exception:
        return _record(now, "", [], "error")

    plan_type = limits.get("planType")
    plan = plan_type.replace("_", " ").title() if isinstance(plan_type, str) else ""
    return _record(now, plan, allowances, "ok")
