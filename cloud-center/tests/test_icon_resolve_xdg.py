"""Application and icon discovery across Nix profile XDG directories."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[2] / ".config/quickshell/overview/services/icon_resolve.py"


def load_resolver():
    spec = importlib.util.spec_from_file_location("icon_resolve_xdg_test", SOURCE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class IconResolveXdgTest(unittest.TestCase):
    def test_missing_icons_share_directory_scan_and_refresh_after_changes(self):
        module = load_resolver()
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / "MixedCase.SVG").write_text("icon")
            with patch.object(module.os, "scandir", wraps=os.scandir) as scan:
                self.assertEqual(module._match_icon_file(folder, "mixedcase"), str(folder / "MixedCase.SVG"))
                self.assertEqual(module._match_icon_file(folder, "missing-one"), "")
                self.assertEqual(module._match_icon_file(folder, "missing-two"), "")
                self.assertEqual(scan.call_count, 1)
                (folder / "NewIcon.PNG").write_text("icon")
                stamp = folder.stat().st_mtime_ns
                os.utime(folder, ns=(stamp + 1, stamp + 1))
                self.assertEqual(module._match_icon_file(folder, "newicon"), str(folder / "NewIcon.PNG"))
                self.assertEqual(scan.call_count, 2)

    def test_case_insensitive_lookup_ignores_directories_and_broken_links(self):
        module = load_resolver()
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / "Example.SVG").mkdir()
            (folder / "Example.PNG").symlink_to(folder / "absent")
            (folder / "Example.XPM").write_text("icon")
            self.assertEqual(module._match_icon_file(folder, "example"), str(folder / "Example.XPM"))

    def test_nix_profile_application_and_theme_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            user = Path(tmp) / "user"
            profile = Path(tmp) / "profile/share"
            theme = profile / "icons/TestTheme"
            theme.mkdir(parents=True)
            with patch.dict(os.environ, {
                "XDG_DATA_HOME": str(user),
                "XDG_DATA_DIRS": f"{profile}:{profile}:/usr/share",
            }):
                module = load_resolver()
            self.assertEqual(module.DESKTOP_DIRS, (
                user / "applications", profile / "applications", Path("/usr/share/applications"),
            ))
            with patch.object(module, "get_icon_theme", return_value="TestTheme"):
                self.assertIn(theme, module.theme_search_roots())

    def test_unset_xdg_variables_keep_standard_locations(self):
        with patch.dict(os.environ, {"XDG_DATA_HOME": "", "XDG_DATA_DIRS": ""}):
            module = load_resolver()
        self.assertEqual(module.DESKTOP_DIRS, (
            Path.home() / ".local/share/applications",
            Path("/usr/local/share/applications"), Path("/usr/share/applications"),
        ))
