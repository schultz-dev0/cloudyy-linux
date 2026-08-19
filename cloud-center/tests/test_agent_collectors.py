from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

from lib.agents.collectors import claude, codex, fireworks
from lib.agents.contract import normalize_record, write_record


NOW = datetime(2026, 8, 14, 12, 0, tzinfo=timezone.utc)
NOW_TEXT = "2026-08-14T12:00:00+00:00"


class _Response:
    def __init__(self, value: object):
        self.value = value

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return json.dumps(self.value).encode()


class AgentCollectorsTest(unittest.TestCase):
    def test_claude_collects_authoritative_scoped_windows(self):
        secret = "claude-secret-value"
        with tempfile.TemporaryDirectory() as tmp:
            credentials = Path(tmp) / "credentials.json"
            credentials.write_text(json.dumps({
                "claudeAiOauth": {
                    "accessToken": secret,
                    "expiresAt": 1_800_000_000_000,
                    "subscriptionType": "max",
                },
            }), encoding="utf-8")
            requests = []

            def opener(request, timeout):
                requests.append((request, timeout))
                return _Response({
                    "five_hour": {
                        "utilization": 12.5,
                        "resets_at": "2026-08-14T15:00:00Z",
                    },
                    "seven_day": {
                        "utilization": 47,
                        "resets_at": "2026-08-19T00:00:00Z",
                    },
                    "seven_day_sonnet": {
                        "utilization": 65.25,
                        "resets_at": "2026-08-20T00:00:00Z",
                    },
                    "seven_day_opus": None,
                })

            record = claude.collect(
                NOW, opener, {"CLAUDE_CREDENTIALS_PATH": str(credentials)},
            )

        self.assertEqual(record, {
            "schemaVersion": 1,
            "recordId": "claude",
            "provider": {"id": "claude", "name": "Claude"},
            "planLabel": "Max",
            "allowances": [
                {
                    "id": "five_hour",
                    "label": "5-hour session",
                    "usedPercent": 12.5,
                    "resetAt": "2026-08-14T15:00:00Z",
                },
                {
                    "id": "seven_day",
                    "label": "Weekly",
                    "usedPercent": 47,
                    "resetAt": "2026-08-19T00:00:00Z",
                },
                {
                    "id": "seven_day_sonnet",
                    "label": "Sonnet weekly",
                    "usedPercent": 65.25,
                    "resetAt": "2026-08-20T00:00:00Z",
                },
            ],
            "dataUpdatedAt": NOW_TEXT,
            "lastAttemptAt": NOW_TEXT,
            "status": {"state": "ok", "message": ""},
        })
        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0][1], 10)
        self.assertEqual(requests[0][0].get_header("Authorization"), f"Bearer {secret}")
        self.assertNotIn(secret, repr(record))
        self.assertIsNotNone(normalize_record(record, NOW))

    def test_claude_missing_or_expired_auth_is_sanitized_unavailable(self):
        cases = [
            {},
            {"claudeAiOauth": {"accessToken": "expired-secret", "expiresAt": 1}},
        ]
        for value in cases:
            with self.subTest(value=value), tempfile.TemporaryDirectory() as tmp:
                credentials = Path(tmp) / "credentials.json"
                credentials.write_text(json.dumps(value), encoding="utf-8")

                record = claude.collect(
                    NOW,
                    lambda *_args: self.fail("network call with unavailable auth"),
                    {"CLAUDE_CREDENTIALS_PATH": str(credentials)},
                )

                self.assertEqual(record["status"], {
                    "state": "unavailable", "message": "Usage unavailable",
                })
                self.assertEqual(record["allowances"], [])
                self.assertNotIn("expired-secret", repr(record))

    def test_claude_http_failure_returns_safe_error_for_prior_data_merge(self):
        secret = "never-return-this-token"
        with tempfile.TemporaryDirectory() as tmp:
            credentials = Path(tmp) / "credentials.json"
            credentials.write_text(json.dumps({"claudeAiOauth": {
                "accessToken": secret, "expiresAt": 1_800_000_000_000,
            }}), encoding="utf-8")

            def fail(*_args):
                raise RuntimeError(f"provider returned {secret} and raw response")

            record = claude.collect(
                NOW, fail, {"CLAUDE_CREDENTIALS_PATH": str(credentials)},
            )

        self.assertEqual(record["status"], {
            "state": "error", "message": "Collection failed",
        })
        self.assertEqual(record["allowances"], [])
        self.assertNotIn(secret, repr(record))
        self.assertNotIn("raw response", repr(record))

    def test_collection_failure_retains_prior_valid_allowances(self):
        prior = {
            "schemaVersion": 1,
            "recordId": "claude",
            "provider": {"id": "claude", "name": "Claude"},
            "planLabel": "Max",
            "allowances": [{
                "id": "five_hour",
                "label": "5-hour session",
                "usedPercent": 40,
                "resetAt": "2026-08-14T15:00:00Z",
            }],
            "dataUpdatedAt": "2026-08-14T11:55:00+00:00",
            "lastAttemptAt": "2026-08-14T11:55:00+00:00",
            "status": {"state": "ok", "message": ""},
        }
        failed = claude.collect(
            NOW,
            lambda *_args: self.fail("missing auth must not open the network"),
            {},
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "claude.json"
            write_record(path, prior)
            write_record(path, failed)
            stored = json.loads(path.read_text(encoding="utf-8"))

        self.assertEqual(stored["allowances"], prior["allowances"])
        self.assertEqual(stored["dataUpdatedAt"], prior["dataUpdatedAt"])
        self.assertEqual(stored["lastAttemptAt"], NOW_TEXT)
        self.assertEqual(stored["status"], {
            "state": "unavailable", "message": "Usage unavailable",
        })

    def test_codex_collects_primary_secondary_and_scoped_windows(self):
        response = {
            "jsonrpc": "2.0",
            "id": 2,
            "result": {
                "rateLimits": {
                    "planType": "plus",
                    "primary": {
                        "usedPercent": 25,
                        "windowDurationMins": 10080,
                        "resetsAt": 1_776_427_200,
                    },
                    "secondary": {
                        "usedPercent": 0.5,
                        "windowDurationMins": 300,
                        "resetsAt": 1_776_945_600,
                    },
                    "credits": None,
                },
                "rateLimitsByLimitId": {
                    "codex_bengalfox": {
                        "limitName": "GPT-5.3-Codex-Spark",
                        "primary": {
                            "usedPercent": 99.5,
                            "windowDurationMins": 300,
                            "resetsAt": 1_776_427_200,
                        },
                    },
                },
            },
        }
        calls = []

        def runner(argv, **kwargs):
            calls.append((argv, kwargs))
            return SimpleNamespace(returncode=0, stdout=json.dumps(response), stderr="")

        record = codex.collect(NOW, runner, {})

        self.assertEqual([item["usedPercent"] for item in record["allowances"]], [25, 0.5, 99.5])
        self.assertEqual(record["allowances"], [
            {
                "id": "primary", "label": "Weekly", "usedPercent": 25,
                "resetAt": "2026-04-17T12:00:00+00:00",
            },
            {
                "id": "secondary", "label": "5-hour session", "usedPercent": 0.5,
                "resetAt": "2026-04-23T12:00:00+00:00",
            },
            {
                "id": "codex_bengalfox-primary",
                "label": "GPT-5.3-Codex-Spark 5-hour session",
                "usedPercent": 99.5,
                "resetAt": "2026-04-17T12:00:00+00:00",
            },
        ])
        self.assertEqual(record["planLabel"], "Plus")
        self.assertEqual(record["status"], {"state": "ok", "message": ""})
        self.assertEqual(calls[0][0], ["codex", "app-server", "--listen", "stdio://"])
        sent = [json.loads(line) for line in calls[0][1]["input"].splitlines()]
        self.assertEqual(sent[1]["method"], "initialized")
        self.assertEqual(sent[2]["method"], "account/rateLimits/read")
        self.assertEqual(calls[0][1]["timeout"], 10)
        self.assertIsNotNone(normalize_record(record, NOW))

    def test_codex_failure_and_rpc_error_never_return_process_output(self):
        secret = "codex-secret-output"
        cases = [
            SimpleNamespace(returncode=1, stdout="", stderr=secret),
            SimpleNamespace(
                returncode=0,
                stdout=json.dumps({"id": 2, "error": {"message": secret}}),
                stderr="",
            ),
        ]
        for completed in cases:
            with self.subTest(returncode=completed.returncode):
                record = codex.collect(NOW, lambda *_args, **_kwargs: completed, {})
                self.assertEqual(record["status"], {
                    "state": "error", "message": "Collection failed",
                })
                self.assertNotIn(secret, repr(record))

    def test_fireworks_does_not_invent_allowance_percentages(self):
        called = False

        def opener(*_args):
            nonlocal called
            called = True
            raise AssertionError("unsupported API must not be called")

        record = fireworks.collect(
            NOW,
            opener,
            {"FIREWORKS_API_KEY": "fireworks-secret", "FIREWORKS_ACCOUNT_ID": "acct"},
        )

        self.assertFalse(called)
        self.assertEqual(record, {
            "schemaVersion": 1,
            "recordId": "fireworks",
            "provider": {"id": "fireworks", "name": "Fireworks"},
            "planLabel": "",
            "allowances": [],
            "dataUpdatedAt": NOW_TEXT,
            "lastAttemptAt": NOW_TEXT,
            "status": {"state": "unavailable", "message": "Usage unavailable"},
        })
        self.assertNotIn("fireworks-secret", repr(record))
        self.assertIsNotNone(normalize_record(record, NOW))


if __name__ == "__main__":
    unittest.main()
