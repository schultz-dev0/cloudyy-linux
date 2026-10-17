"""NixOS updater confirmation, argument handling, and activation ordering."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "lib/cloudyy-nixos/update.sh"


class NixosUpdateTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo with spaces"
        self.repo.mkdir()
        (self.repo / "flake.nix").write_text("{}\n")
        (self.repo / "flake.lock").write_text("original lock\n")
        self.config = self.root / "nixos.json"
        self.config.write_text(json.dumps({"repo": str(self.repo), "configuration": "cloudyy-laptop"}))
        self.log = self.root / "commands.jsonl"
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        fake = '''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
tool = pathlib.Path(sys.argv[0]).name
with open(os.environ["COMMAND_LOG"], "a") as log:
    log.write(json.dumps([tool, *args]) + "\\n")
if tool == "nix" and args[0] == os.environ.get("FAIL_STEP"):
    sys.exit(17)
if tool == "nix" and args[:2] == ["flake", "update"]:
    repo = pathlib.Path(args[args.index("--flake") + 1])
    (repo / "flake.lock").write_text("updated lock\\n")
'''
        for name in ("nix", "sudo"):
            path = fake_bin / name
            path.write_text(fake)
            path.chmod(0o755)
        self.environment = os.environ | {
            "PATH": f"{fake_bin}:{os.environ['PATH']}",
            "CLOUDYY_NIXOS_CONFIG": str(self.config),
            "XDG_STATE_HOME": str(self.root / "state"),
            "COMMAND_LOG": str(self.log),
        }

    def run_update(self, *args: str, answer: str = "y\n"):
        return subprocess.run(
            ["bash", str(SCRIPT), *args], input=answer, env=self.environment,
            text=True, capture_output=True,
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_dry_run_makes_no_changes(self):
        result = self.run_update("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertEqual((self.repo / "flake.lock").read_text(), "original lock\n")

    def test_declining_makes_no_changes(self):
        result = self.run_update(answer="n\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [])

    def test_success_builds_before_activation_and_preserves_previous_lock(self):
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual([c[:2] for c in calls], [["nix", "flake"], ["nix", "build"], ["sudo", "nixos-rebuild"]])
        self.assertEqual(calls[0][-1], str(self.repo))
        self.assertEqual(calls[2][-1], f"path:{self.repo}#cloudyy-laptop")
        backups = list((self.root / "state/cloudyy/updates").glob("*/flake.lock.before"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "original lock\n")

    def test_failed_build_never_activates(self):
        self.environment["FAIL_STEP"] = "build"
        result = self.run_update()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(c[0] == "sudo" for c in self.calls()))
        self.assertIn("Update stopped", result.stdout)

    def test_failed_input_update_never_builds_or_activates(self):
        self.environment["FAIL_STEP"] = "flake"
        result = self.run_update()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls()), 1)

    def test_invalid_target_is_rejected_before_commands(self):
        self.config.write_text(json.dumps({"repo": str(self.repo), "configuration": "bad;target"}))
        result = self.run_update()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])
