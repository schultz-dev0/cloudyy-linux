"""Behavioral coverage for fresh Spotlight catalogs and live filesystem search."""
from __future__ import annotations

import importlib.util
import json
import os
import select
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
QS = ROOT / ".config/quickshell"
SEARCH = QS / "modules/spotlight/search-files.py"
WATCH = QS / "overview/services/watch_paths.py"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SpotlightSearchTest(unittest.TestCase):
    def test_settings_metadata_includes_yaml_rows_and_native_pages_without_live_queries(self):
        module = load_module("settings_search", ROOT / "cloud-center/scripts/search-catalog.py")
        with patch("subprocess.run", side_effect=AssertionError("must not query devices")):
            rows = module.build_catalog()
        self.assertTrue(any(row["label"] == "Keyboard Layout" and row["page"] == "input" for row in rows))
        self.assertTrue(any(row["page"] == "__mon__" for row in rows))
        self.assertTrue(any(row["page"] == "__audio__" for row in rows))
        self.assertEqual(len(rows), len({row["id"] for row in rows}))

    def test_new_deep_files_directories_and_literal_special_characters(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            env = {**os.environ, "HOME": tmp}
            deep = home / "one/two/three/four/five"
            deep.mkdir(parents=True)
            name = "fresh[entry]\nwith spaces.txt"
            file = deep / name
            file.touch()
            folder = deep / "fresh[entry] folder"
            folder.mkdir()
            ignored = home / "node_modules"
            ignored.mkdir()
            (ignored / name).touch()
            result = subprocess.run([sys.executable, str(SEARCH), "fresh[entry]"],
                                    env=env, capture_output=True, text=True, check=True, timeout=5)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual({row["path"].rstrip("/") for row in rows}, {str(file), str(folder)})
            file.unlink()
            result = subprocess.run([sys.executable, str(SEARCH), "fresh[entry]"],
                                    env=env, capture_output=True, text=True, check=True, timeout=5)
            self.assertNotIn(str(file), {json.loads(line)["path"] for line in result.stdout.splitlines()})

    def test_watcher_handles_missing_roots_nested_changes_and_atomic_replacements(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "applications"
            proc = subprocess.Popen([sys.executable, str(WATCH), "--recursive", str(root)],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                def read_event():
                    self.assertTrue(select.select([proc.stdout], [], [], 5)[0], "watcher timed out")
                    return proc.stdout.readline().strip()

                self.assertEqual(read_event(), "ready")
                nested = root / "nested"
                nested.mkdir(parents=True)
                self.assertEqual(read_event(), "changed")
                desktop = nested / "test.desktop"
                desktop.write_text("first")
                self.assertEqual(read_event(), "changed")
                replacement = nested / "replacement"
                replacement.write_text("second")
                replacement.replace(desktop)
                self.assertEqual(read_event(), "changed")
                desktop.unlink()
                self.assertEqual(read_event(), "changed")
            finally:
                proc.terminate()
                proc.communicate(timeout=5)

    def test_app_cache_detects_same_second_edits_and_nested_xdg_entries(self):
        sys.path.insert(0, str(QS / "overview/services"))
        module = load_module("apps_catalog", QS / "modules/commandcenter/applibrary/apps-catalog.py")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            nested = root / "nested"
            nested.mkdir()
            desktop = nested / "app.desktop"
            desktop.write_text("[Desktop Entry]\nName=Fresh App\nExec=true\nIcon=test\n")
            with patch.object(module, "DESKTOP_DIRS", (root,)), \
                 patch.object(module, "get_icon_theme", return_value="test"), \
                 patch.object(module, "resolve_app_icon", return_value=""):
                first = module.desktop_stamp()
                stat = desktop.stat()
                desktop.write_text(desktop.read_text().replace("Fresh App", "Other App"))
                os.utime(desktop, ns=(stat.st_atime_ns, stat.st_mtime_ns + 1))
                self.assertNotEqual(first, module.desktop_stamp())
                apps = module.build_catalog()
            self.assertEqual(apps[0]["id"], "nested-app")
            self.assertEqual(apps[0]["name"], "Other App")
