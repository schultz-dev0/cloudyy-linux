from __future__ import annotations

import json
import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

from lib.agents.contract import load_usage_directory, normalize_record, write_record


NOW = datetime(2026, 8, 14, 12, 0, tzinfo=timezone.utc)


def _record(**overrides) -> dict:
    record = {
        "schemaVersion": 1,
        "recordId": "claude",
        "provider": {"id": "anthropic", "name": "Anthropic"},
        "planLabel": "Claude Pro",
        "allowances": [{
            "id": "five-hour",
            "label": "5-hour window",
            "usedPercent": 25.5,
            "resetAt": "2026-08-14T15:00:00Z",
        }],
        "dataUpdatedAt": "2026-08-14T11:45:00Z",
        "lastAttemptAt": "2026-08-14T11:45:00Z",
        "status": {"state": "ok", "message": ""},
    }
    record.update(overrides)
    return record


class AgentsRecordValidationTest(unittest.TestCase):
    def test_normalizes_valid_record_to_known_fields(self):
        value = _record(untrustedSecret="must-not-survive")

        result = normalize_record(value, NOW)

        self.assertEqual(result, {**_record(), "stale": False})

    def test_rejects_malformed_records_and_unknown_versions(self):
        invalid_values = [
            None,
            [],
            _record(schemaVersion=2),
            _record(recordId=""),
            _record(provider={"id": "anthropic"}),
            _record(planLabel=None),
            _record(allowances="five-hour"),
            _record(status={"state": "retrying", "message": ""}),
        ]

        for value in invalid_values:
            with self.subTest(value=value):
                self.assertIsNone(normalize_record(value, NOW))

    def test_schema_version_requires_exact_integer_type(self):
        for version in (True, 1.0):
            with self.subTest(version=version):
                self.assertIsNone(normalize_record(
                    _record(schemaVersion=version), NOW,
                ))

    def test_rejects_invalid_percentages(self):
        for percentage in (-0.1, 100.1, True, "25"):
            with self.subTest(percentage=percentage):
                allowances = [{**_record()["allowances"][0], "usedPercent": percentage}]
                self.assertIsNone(normalize_record(
                    _record(allowances=allowances), NOW,
                ))

    def test_rejects_invalid_or_naive_timestamps(self):
        cases = [
            {"dataUpdatedAt": "not-a-time"},
            {"lastAttemptAt": "2026-08-14T11:45:00"},
            {"allowances": [{
                **_record()["allowances"][0],
                "resetAt": "Friday afternoon",
            }]},
        ]

        for override in cases:
            with self.subTest(override=override):
                self.assertIsNone(normalize_record(_record(**override), NOW))

    def test_allows_unknown_reset_time_as_null(self):
        allowances = [{**_record()["allowances"][0], "resetAt": None}]

        result = normalize_record(_record(allowances=allowances), NOW)

        self.assertIsNotNone(result)
        self.assertIsNone(result["allowances"][0]["resetAt"])

    def test_marks_record_stale_at_thirty_minutes(self):
        updated = NOW - timedelta(minutes=30)

        result = normalize_record(
            _record(dataUpdatedAt=updated.isoformat()), NOW,
        )

        self.assertTrue(result["stale"])

    def test_omits_record_at_twenty_four_hours(self):
        updated = NOW - timedelta(hours=24)

        self.assertIsNone(normalize_record(
            _record(dataUpdatedAt=updated.isoformat()), NOW,
        ))

    def test_allows_at_most_five_minutes_of_clock_skew(self):
        skewed = NOW + timedelta(minutes=5)

        result = normalize_record(_record(
            dataUpdatedAt=skewed.isoformat(),
            lastAttemptAt=skewed.isoformat(),
        ), NOW)

        self.assertIsNotNone(result)
        self.assertFalse(result["stale"])

    def test_rejects_materially_future_freshness_timestamps(self):
        future = (NOW + timedelta(minutes=5, seconds=1)).isoformat()

        for field in ("dataUpdatedAt", "lastAttemptAt"):
            with self.subTest(field=field):
                self.assertIsNone(normalize_record(_record(**{field: future}), NOW))

    def test_status_messages_are_generic_and_cannot_expose_secrets(self):
        value = _record(status={
            "state": "error",
            "message": "Bearer secret-token from https://api.example.test/raw?key=abc",
        })

        result = normalize_record(value, NOW)

        self.assertEqual(result["status"], {
            "state": "error",
            "message": "Collection failed",
        })
        self.assertNotIn("secret-token", json.dumps(result))


class AgentsUsageDirectoryTest(unittest.TestCase):
    def test_malformed_file_does_not_reject_valid_peer(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / "broken.json").write_text("{not json", encoding="utf-8")
            (path / "claude.json").write_text(json.dumps(_record()), encoding="utf-8")

            records = load_usage_directory(path, NOW)

        self.assertEqual([record["recordId"] for record in records], ["claude"])

    def test_invalid_utf8_file_does_not_reject_valid_peer(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / "broken.json").write_bytes(b"\xff")
            (path / "claude.json").write_text(json.dumps(_record()), encoding="utf-8")

            records = load_usage_directory(path, NOW)

        self.assertEqual([record["recordId"] for record in records], ["claude"])

    def test_oversized_json_integer_does_not_reject_valid_peer(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / "broken.json").write_text(
                '{"schemaVersion":' + "9" * 5000 + "}", encoding="utf-8",
            )
            (path / "claude.json").write_text(json.dumps(_record()), encoding="utf-8")

            records = load_usage_directory(path, NOW)

        self.assertEqual([record["recordId"] for record in records], ["claude"])

    def test_file_errors_do_not_log_secret_exception_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            broken = path / "broken.json"
            valid = path / "claude.json"
            broken.touch()
            valid.touch()

            def _read_text(record_path, *args, **kwargs):
                if record_path == broken:
                    raise OSError("Bearer secret-token from private response")
                return json.dumps(_record())

            with mock.patch.object(Path, "read_text", _read_text):
                with self.assertLogs("lib.agents.contract", level="WARNING") as captured:
                    records = load_usage_directory(path, NOW)

        messages = "\n".join(captured.output)
        self.assertEqual([record["recordId"] for record in records], ["claude"])
        self.assertIn("read failure", messages)
        self.assertNotIn("secret-token", messages)
        self.assertNotIn("private response", messages)

    def test_parser_errors_do_not_log_secret_exception_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            broken = path / "broken.json"
            valid = path / "claude.json"
            broken.write_text("broken", encoding="utf-8")
            valid.write_text(json.dumps(_record()), encoding="utf-8")
            real_loads = json.loads

            def _loads(value):
                if value == "broken":
                    raise ValueError("Bearer parser-secret from private response")
                return real_loads(value)

            with mock.patch("lib.agents.contract.json.loads", side_effect=_loads):
                with self.assertLogs("lib.agents.contract", level="WARNING") as captured:
                    records = load_usage_directory(path, NOW)

        messages = "\n".join(captured.output)
        self.assertEqual([record["recordId"] for record in records], ["claude"])
        self.assertIn("parse failure", messages)
        self.assertNotIn("parser-secret", messages)
        self.assertNotIn("private response", messages)

    def test_logs_do_not_expose_secret_bearing_filenames(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / "Bearer-secret-token.json").write_text("broken", encoding="utf-8")

            with self.assertLogs("lib.agents.contract", level="WARNING") as captured:
                load_usage_directory(path, NOW)

        messages = "\n".join(captured.output)
        self.assertIn("parse failure", messages)
        self.assertNotIn("secret-token", messages)

    def test_missing_directory_is_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            missing = Path(tmp) / "missing"
            self.assertEqual(load_usage_directory(missing, NOW), [])

    def test_write_is_atomic_and_private(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "usage" / "claude.json"
            replace_calls = []
            real_replace = os.replace

            def _replace(source, destination):
                replace_calls.append((Path(source), Path(destination)))
                self.assertNotEqual(Path(source), path)
                self.assertEqual(Path(destination), path)
                real_replace(source, destination)

            with mock.patch("lib.agents.contract.os.replace", side_effect=_replace):
                write_record(path, _record())

            self.assertEqual(len(replace_calls), 1)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(path.read_text(encoding="utf-8")), _record())
            self.assertEqual(list(path.parent.iterdir()), [path])

    def test_failed_write_retains_last_valid_usage_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "claude.json"
            write_record(path, _record())
            failed = _record(
                planLabel="",
                allowances=[],
                dataUpdatedAt="2026-08-14T11:55:00Z",
                lastAttemptAt="2026-08-14T12:00:00Z",
                status={"state": "error", "message": "token sk-secret was rejected"},
            )

            write_record(path, failed)
            stored = json.loads(path.read_text(encoding="utf-8"))

        self.assertEqual(stored["planLabel"], "Claude Pro")
        self.assertEqual(stored["allowances"], _record()["allowances"])
        self.assertEqual(stored["dataUpdatedAt"], "2026-08-14T11:45:00Z")
        self.assertEqual(stored["lastAttemptAt"], "2026-08-14T12:00:00Z")
        self.assertEqual(stored["status"], {
            "state": "error",
            "message": "Collection failed",
        })
        self.assertNotIn("sk-secret", json.dumps(stored))

    def test_failed_write_replaces_oversized_integer_prior_record(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "claude.json"
            path.write_text(
                '{"Bearer-secret":' + "9" * 5000 + "}", encoding="utf-8",
            )
            failed = _record(
                planLabel="Usage unavailable",
                allowances=[],
                dataUpdatedAt="2026-08-14T11:55:00Z",
                lastAttemptAt="2026-08-14T12:00:00Z",
                status={"state": "error", "message": "token sk-new-secret failed"},
            )

            with self.assertNoLogs("lib.agents.contract", level="WARNING"):
                write_record(path, failed)
            stored = json.loads(path.read_text(encoding="utf-8"))

        self.assertEqual(stored, {
            **failed,
            "status": {"state": "error", "message": "Collection failed"},
        })
        self.assertNotIn("Bearer-secret", json.dumps(stored))
        self.assertNotIn("sk-new-secret", json.dumps(stored))

    def test_failed_write_does_not_merge_prior_record_with_different_identity(self):
        cases = [
            {"recordId": "different-record"},
            {"provider": {"id": "openai", "name": "OpenAI"}},
            {"provider": {"id": "anthropic", "name": "Different Name"}},
        ]

        for index, prior_override in enumerate(cases):
            with self.subTest(prior_override=prior_override):
                with tempfile.TemporaryDirectory() as tmp:
                    path = Path(tmp) / f"claude-{index}.json"
                    write_record(path, _record(**prior_override))
                    failed = _record(
                        planLabel="Usage unavailable",
                        allowances=[],
                        dataUpdatedAt="2026-08-14T11:55:00Z",
                        lastAttemptAt="2026-08-14T12:00:00Z",
                        status={"state": "error", "message": "private failure"},
                    )

                    write_record(path, failed)
                    stored = json.loads(path.read_text(encoding="utf-8"))

                self.assertEqual(stored, {
                    **failed,
                    "status": {"state": "error", "message": "Collection failed"},
                })


if __name__ == "__main__":
    unittest.main()
