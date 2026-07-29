import importlib.util
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[2] / ".config/quickshell/overview/services/cursor_workspace.py"
SPEC = importlib.util.spec_from_file_location("cursor_workspace", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
read_recent_workspaces = MODULE.read_recent_workspaces


class CursorWorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.db = Path(self.temp_dir.name) / "state.vscdb"
        with sqlite3.connect(self.db) as connection:
            connection.execute("CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value TEXT)")

    def insert(self, key, value):
        with sqlite3.connect(self.db) as connection:
            connection.execute("INSERT INTO ItemTable(key, value) VALUES (?, ?)", (key, value))

    def test_reads_valid_existing_file_uris_in_mru_order(self):
        self.insert("history.recentlyOpenedPathsList", json.dumps({"entries": [
            {"folderUri": "file:///work/one"},
            {"folderUri": "file:///work/two"},
        ]}))
        existing = {Path("/work/one"), Path("/work/two")}
        self.assertEqual(
            read_recent_workspaces(self.db, lambda path: path in existing),
            ["file:///work/one", "file:///work/two"],
        )

    def test_preserves_remote_workspace_uri(self):
        self.insert("history.recentlyOpenedPathsList", json.dumps({"entries": [
            {"workspaceUri": "vscode-remote://ssh-remote+host/work/project"},
        ]}))
        self.assertEqual(
            read_recent_workspaces(self.db, lambda _path: False),
            ["vscode-remote://ssh-remote+host/work/project"],
        )

    def test_rejects_nonexistent_local_paths_and_deduplicates(self):
        self.insert("history.recentlyOpenedPathsList", json.dumps({"entries": [
            {"folderUri": "file:///missing"},
            {"folderUri": "file:///work/one"},
            {"folderUri": "file:///work/one"},
        ]}))
        self.assertEqual(
            read_recent_workspaces(self.db, lambda path: path == Path("/work/one")),
            ["file:///work/one"],
        )

    def test_malformed_json_and_absent_record_are_empty(self):
        self.insert("history.recentlyOpenedPathsList", "not-json")
        self.assertEqual(read_recent_workspaces(self.db, lambda _path: True), [])
        with sqlite3.connect(self.db) as connection:
            connection.execute("DELETE FROM ItemTable")
        self.assertEqual(read_recent_workspaces(self.db, lambda _path: True), [])

    def test_missing_database_is_empty(self):
        self.assertEqual(
            read_recent_workspaces(Path(self.temp_dir.name) / "missing.db", lambda _path: True),
            [],
        )


if __name__ == "__main__":
    unittest.main()
