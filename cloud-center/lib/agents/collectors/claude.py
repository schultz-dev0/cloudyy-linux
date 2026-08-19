"""Collect Claude subscription allowance windows from the OAuth usage API."""
from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from urllib.request import Request


_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
_WINDOWS = (
    ("five_hour", "5-hour session"),
    ("seven_day", "Weekly"),
    ("seven_day_oauth_apps", "OAuth apps weekly"),
    ("seven_day_opus", "Opus weekly"),
    ("seven_day_sonnet", "Sonnet weekly"),
)


def _record(now: datetime, plan: str, allowances: list[dict], state: str) -> dict:
    timestamp = now.isoformat()
    messages = {"ok": "", "unavailable": "Usage unavailable", "error": "Collection failed"}
    return {
        "schemaVersion": 1,
        "recordId": "claude",
        "provider": {"id": "claude", "name": "Claude"},
        "planLabel": plan,
        "allowances": allowances,
        "dataUpdatedAt": timestamp,
        "lastAttemptAt": timestamp,
        "status": {"state": state, "message": messages[state]},
    }


def _credentials_path(env: dict) -> Path | None:
    explicit = env.get("CLAUDE_CREDENTIALS_PATH")
    if explicit:
        return Path(explicit)
    config_dir = env.get("CLAUDE_CONFIG_DIR")
    if config_dir:
        return Path(config_dir) / ".credentials.json"
    home = env.get("HOME")
    return Path(home) / ".claude" / ".credentials.json" if home else None


def collect(now: datetime, opener, env: dict) -> dict:
    path = _credentials_path(env)
    try:
        credentials = json.loads(path.read_text(encoding="utf-8")) if path else {}
    except (OSError, ValueError, json.JSONDecodeError):
        credentials = {}
    oauth = credentials.get("claudeAiOauth") if isinstance(credentials, dict) else None
    token = oauth.get("accessToken") if isinstance(oauth, dict) else None
    expires_at = oauth.get("expiresAt") if isinstance(oauth, dict) else None
    if not isinstance(token, str) or not token:
        return _record(now, "", [], "unavailable")
    if not isinstance(expires_at, (int, float)) or expires_at <= now.timestamp() * 1000:
        return _record(now, "", [], "unavailable")

    request = Request(_USAGE_URL, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "anthropic-beta": "oauth-2025-04-20",
    })
    try:
        with opener(request, timeout=10) as response:
            payload = json.loads(response.read())
        if not isinstance(payload, dict):
            raise ValueError("invalid usage response")
        allowances = []
        for window_id, label in _WINDOWS:
            window = payload.get(window_id)
            if not isinstance(window, dict):
                continue
            utilization = window.get("utilization")
            reset_at = window.get("resets_at")
            if isinstance(utilization, bool) or not isinstance(utilization, (int, float)):
                continue
            if not 0 <= utilization <= 100:
                continue
            if reset_at is not None:
                if not isinstance(reset_at, str):
                    continue
                try:
                    parsed_reset = datetime.fromisoformat(reset_at.replace("Z", "+00:00"))
                except ValueError:
                    continue
                if parsed_reset.tzinfo is None or parsed_reset.utcoffset() is None:
                    continue
            allowances.append({
                "id": window_id,
                "label": label,
                "usedPercent": utilization,
                "resetAt": reset_at,
            })
        if not allowances:
            return _record(now, "", [], "unavailable")
    except Exception:
        return _record(now, "", [], "error")

    subscription = oauth.get("subscriptionType")
    plan = subscription.replace("_", " ").title() if isinstance(subscription, str) else ""
    return _record(now, plan, allowances, "ok")
