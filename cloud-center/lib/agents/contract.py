"""Validate and persist versioned agent usage records."""
from __future__ import annotations

import json
import logging
import os
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

log = logging.getLogger(__name__)

SCHEMA_VERSION = 1
STALE_AFTER = timedelta(minutes=30)
OMIT_AFTER = timedelta(hours=24)
MAX_CLOCK_SKEW = timedelta(minutes=5)
STATUS_MESSAGES = {
    "ok": "",
    "unavailable": "Usage unavailable",
    "error": "Collection failed",
}


def _nonempty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _timestamp(value: object) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        return None
    return parsed


def _validated_record(value: object) -> dict | None:
    if not isinstance(value, dict):
        return None
    schema_version = value.get("schemaVersion")
    if type(schema_version) is not int or schema_version != SCHEMA_VERSION:
        return None
    if not _nonempty_string(value.get("recordId")):
        return None

    provider = value.get("provider")
    if not isinstance(provider, dict):
        return None
    if not _nonempty_string(provider.get("id")) or not _nonempty_string(provider.get("name")):
        return None

    plan_label = value.get("planLabel")
    allowances = value.get("allowances")
    if not isinstance(plan_label, str) or not isinstance(allowances, list):
        return None

    normalized_allowances = []
    for allowance in allowances:
        if not isinstance(allowance, dict):
            return None
        used_percent = allowance.get("usedPercent")
        reset_at = allowance.get("resetAt")
        if not _nonempty_string(allowance.get("id")):
            return None
        if not _nonempty_string(allowance.get("label")):
            return None
        if isinstance(used_percent, bool) or not isinstance(used_percent, (int, float)):
            return None
        if not 0 <= used_percent <= 100:
            return None
        if reset_at is not None and _timestamp(reset_at) is None:
            return None
        normalized_allowances.append({
            "id": allowance["id"],
            "label": allowance["label"],
            "usedPercent": used_percent,
            "resetAt": reset_at,
        })

    data_updated_at = value.get("dataUpdatedAt")
    last_attempt_at = value.get("lastAttemptAt")
    if _timestamp(data_updated_at) is None or _timestamp(last_attempt_at) is None:
        return None

    status = value.get("status")
    if not isinstance(status, dict) or status.get("state") not in STATUS_MESSAGES:
        return None
    if not isinstance(status.get("message"), str):
        return None
    state = status["state"]

    return {
        "schemaVersion": SCHEMA_VERSION,
        "recordId": value["recordId"],
        "provider": {"id": provider["id"], "name": provider["name"]},
        "planLabel": plan_label,
        "allowances": normalized_allowances,
        "dataUpdatedAt": data_updated_at,
        "lastAttemptAt": last_attempt_at,
        "status": {"state": state, "message": STATUS_MESSAGES[state]},
    }


def normalize_record(value: object, now: datetime) -> dict | None:
    """Return a safe current record, or None for invalid or expired input."""
    record = _validated_record(value)
    if record is None:
        return None
    updated_at = _timestamp(record["dataUpdatedAt"])
    attempted_at = _timestamp(record["lastAttemptAt"])
    if updated_at - now > MAX_CLOCK_SKEW or attempted_at - now > MAX_CLOCK_SKEW:
        return None
    age = now - updated_at
    if age >= OMIT_AFTER:
        return None
    record["stale"] = age >= STALE_AFTER
    return record


def write_record(path: Path, record: dict) -> None:
    """Safely replace one private record, preserving usage after a failed attempt."""
    safe_record = _validated_record(record)
    if safe_record is None:
        raise ValueError("invalid agent usage record")

    if safe_record["status"]["state"] != "ok":
        try:
            previous = _validated_record(json.loads(path.read_text(encoding="utf-8")))
        except (OSError, ValueError, json.JSONDecodeError):
            previous = None
        if (
            previous is not None
            and previous["recordId"] == safe_record["recordId"]
            and previous["provider"] == safe_record["provider"]
        ):
            previous["lastAttemptAt"] = safe_record["lastAttemptAt"]
            previous["status"] = safe_record["status"]
            safe_record = previous

    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
            descriptor = -1
            json.dump(safe_record, temporary_file, separators=(",", ":"))
            temporary_file.write("\n")
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_path, path)
        path.chmod(0o600)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            temporary_path.unlink()
        except FileNotFoundError:
            pass


def load_usage_directory(path: Path, now: datetime) -> list[dict]:
    """Load valid, non-expired usage records without cross-file failures."""
    records = []
    try:
        files = sorted(path.glob("*.json"))
    except OSError:
        log.warning("Unable to list agent usage records: directory read failure")
        return records

    for record_path in files:
        try:
            serialized = record_path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            log.warning("Ignoring agent usage record: read failure")
            continue
        try:
            value = json.loads(serialized)
        except (ValueError, json.JSONDecodeError):
            log.warning("Ignoring agent usage record: parse failure")
            continue
        record = normalize_record(value, now)
        if record is not None:
            records.append(record)
    return records
