"""Report Fireworks allowance availability without deriving unsupported quotas."""
from __future__ import annotations

from datetime import datetime


def collect(now: datetime, opener, env: dict) -> dict:
    timestamp = now.isoformat()
    return {
        "schemaVersion": 1,
        "recordId": "fireworks",
        "provider": {"id": "fireworks", "name": "Fireworks"},
        "planLabel": "",
        "allowances": [],
        "dataUpdatedAt": timestamp,
        "lastAttemptAt": timestamp,
        "status": {"state": "unavailable", "message": "Usage unavailable"},
    }
