"""Sandbox tests for the privileged Zen live-theme bridge installer."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "install/packages/zen-live-theme.sh"
PREF = ROOT / "install/assets/zen/cloudyy-autoconfig.js"
CFG = ROOT / "install/assets/zen/cloudyy.cfg"
OWNER_MARKER = "CLOUDYY-ZEN-LIVE-THEME: zen-live-theme-v1"


class ZenLiveThemeInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cloudyy-zen-install-")
        self.root = Path(self.temp.name)
        self.zen = self.root / "zen"
        self.pref_dir = self.zen / "defaults/pref"
        self.pref_dir.mkdir(parents=True)
        self.channel_pref = self.pref_dir / "channel-prefs.js"
        self.channel_pref.write_text('pref("app.update.channel", "release");\n')
        self.home = self.root / "home"
        self.config = self.root / "config"
        self.profile = self.config / "zen/profile.default"
        self.profile.mkdir(parents=True)
        (self.config / "zen/profiles.ini").write_text(
            "[Profile0]\nIsRelative=1\nPath=profile.default\n"
        )

    def tearDown(self):
        self.temp.cleanup()

    def run_script(self, action: str, **env: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(SCRIPT), action],
            env=os.environ
            | {
                "CLOUDYY_ZEN_INSTALL_ROOT": str(self.zen),
                "HOME": str(self.home),
                "XDG_CONFIG_HOME": str(self.config),
            }
            | env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_install_verify_and_remove_owned_assets(self):
        installed = self.run_script("install")
        self.assertEqual(installed.returncode, 0, installed.stderr)
        self.assertEqual((self.zen / "cloudyy.cfg").read_bytes(), CFG.read_bytes())
        self.assertEqual(
            (self.pref_dir / "cloudyy-autoconfig.js").read_bytes(),
            PREF.read_bytes(),
        )
        self.assertEqual((self.zen / "cloudyy.cfg").stat().st_mode & 0o777, 0o644)
        self.assertEqual(
            (self.pref_dir / "cloudyy-autoconfig.js").stat().st_mode & 0o777,
            0o644,
        )
        self.assertEqual(self.run_script("verify").returncode, 0)
        self.assertEqual(self.run_script("install").returncode, 0)
        self.assertEqual(self.run_script("remove").returncode, 0)
        self.assertFalse((self.zen / "cloudyy.cfg").exists())
        self.assertFalse((self.pref_dir / "cloudyy-autoconfig.js").exists())
        self.assertEqual(
            self.channel_pref.read_text(), 'pref("app.update.channel", "release");\n'
        )

    def test_missing_zen_root_is_unavailable(self):
        shutil.rmtree(self.zen)

        result = self.run_script("install")

        self.assertEqual(result.returncode, 2, result.stderr)

    def test_competing_config_filename_is_preserved_without_writes(self):
        competing = self.pref_dir / "existing-autoconfig.js"
        contents = 'pref("general.config.filename", "personal.cfg");\n'
        competing.write_text(contents)

        result = self.run_script("install")

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(competing.read_text(), contents)
        self.assertFalse((self.zen / "cloudyy.cfg").exists())
        self.assertFalse((self.pref_dir / "cloudyy-autoconfig.js").exists())

    def test_occupied_destination_files_are_preserved(self):
        targets = (
            self.zen / "cloudyy.cfg",
            self.pref_dir / "cloudyy-autoconfig.js",
        )
        for occupied in targets:
            with self.subTest(occupied=occupied):
                for target in targets:
                    target.unlink(missing_ok=True)
                occupied.write_text("user-owned\n")

                result = self.run_script("install")

                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(occupied.read_text(), "user-owned\n")
                other = targets[1] if occupied == targets[0] else targets[0]
                self.assertFalse(other.exists())

    def test_symlink_destination_is_preserved(self):
        outside = self.root / "outside.cfg"
        outside.write_text("user-owned\n")
        target = self.zen / "cloudyy.cfg"
        target.symlink_to(outside)

        result = self.run_script("install")

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertTrue(target.is_symlink())
        self.assertEqual(outside.read_text(), "user-owned\n")

    def test_older_owned_assets_are_upgraded(self):
        old = f"// {OWNER_MARKER}\n// old version\n"
        (self.zen / "cloudyy.cfg").write_text(old)
        (self.pref_dir / "cloudyy-autoconfig.js").write_text(
            f'// {OWNER_MARKER}\npref("general.config.filename", "cloudyy.cfg");\n'
        )

        result = self.run_script("install")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.zen / "cloudyy.cfg").read_bytes(), CFG.read_bytes())
        self.assertEqual(
            (self.pref_dir / "cloudyy-autoconfig.js").read_bytes(),
            PREF.read_bytes(),
        )

    def test_altered_owned_asset_fails_verify_but_is_removable(self):
        self.assertEqual(self.run_script("install").returncode, 0)
        cfg_target = self.zen / "cloudyy.cfg"
        cfg_target.write_text(f"// {OWNER_MARKER}\n// locally altered\n")

        verified = self.run_script("verify")
        removed = self.run_script("remove")

        self.assertEqual(verified.returncode, 1, verified.stderr)
        self.assertEqual(removed.returncode, 0, removed.stderr)
        self.assertFalse(cfg_target.exists())
        self.assertFalse((self.pref_dir / "cloudyy-autoconfig.js").exists())
        self.assertTrue(self.channel_pref.exists())

    def test_verify_rejects_a_competing_config_filename(self):
        self.assertEqual(self.run_script("install").returncode, 0)
        competing = self.pref_dir / "personal-autoconfig.js"
        competing.write_text('pref("general.config.filename", "personal.cfg");\n')

        result = self.run_script("verify")

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertTrue(competing.exists())

    def test_remove_preserves_unowned_destination_files(self):
        pref_target = self.pref_dir / "cloudyy-autoconfig.js"
        cfg_target = self.zen / "cloudyy.cfg"
        pref_target.write_text("user preference\n")
        cfg_target.write_text("user config\n")

        result = self.run_script("remove")

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(pref_target.read_text(), "user preference\n")
        self.assertEqual(cfg_target.read_text(), "user config\n")

    def test_remove_cleans_owned_profile_and_bridge_while_preserving_unrelated_data(self):
        self.assertEqual(self.run_script("install").returncode, 0)
        manifest = self.profile / "zen-themes.json"
        manifest.write_text(json.dumps({
            "personal": {"enabled": False},
            "cloudyy-theme": {"cloudyyOwner": "zen-live-theme-v1", "enabled": True},
        }) + "\n")
        mod = self.profile / "chrome/zen-themes/cloudyy-theme"
        mod.mkdir(parents=True)
        link = mod / "chrome.css"
        link.symlink_to(self.root / "state/cloudyy/current/theme/applications/zen.css")
        personal = self.profile / "chrome/userChrome.css"
        personal.write_text("/* personal */\n")

        result = self.run_script(
            "remove", XDG_STATE_HOME=str(self.root / "state")
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(manifest.read_text()), {"personal": {"enabled": False}})
        self.assertFalse(mod.exists())
        self.assertEqual(personal.read_text(), "/* personal */\n")
        self.assertFalse((self.zen / "cloudyy.cfg").exists())
        self.assertFalse((self.pref_dir / "cloudyy-autoconfig.js").exists())

    def test_profile_cleanup_conflict_preserves_bridge(self):
        self.assertEqual(self.run_script("install").returncode, 0)
        manifest = self.profile / "zen-themes.json"
        manifest.write_text(
            '{"cloudyy-theme":{"cloudyyOwner":"someone-else"}}\n'
        )

        result = self.run_script("remove")

        self.assertEqual(result.returncode, 1)
        self.assertTrue((self.zen / "cloudyy.cfg").exists())
        self.assertTrue((self.pref_dir / "cloudyy-autoconfig.js").exists())
        self.assertIn("someone-else", manifest.read_text())

    def test_second_write_failure_removes_new_first_target(self):
        fake_bin = self._failing_install_bin()

        result = self.run_script(
            "install",
            PATH=f"{fake_bin}:{os.environ['PATH']}",
            CLOUDYY_FAIL_INSTALL_TARGET=str(self.zen / "cloudyy.cfg"),
        )

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertFalse((self.pref_dir / "cloudyy-autoconfig.js").exists())
        self.assertFalse((self.zen / "cloudyy.cfg").exists())

    def test_second_write_failure_restores_previous_first_target(self):
        previous = (
            f'// {OWNER_MARKER}\npref("general.config.filename", "cloudyy.cfg");\n'
            "// old version\n"
        )
        pref_target = self.pref_dir / "cloudyy-autoconfig.js"
        pref_target.write_text(previous)
        fake_bin = self._failing_install_bin()

        result = self.run_script(
            "install",
            PATH=f"{fake_bin}:{os.environ['PATH']}",
            CLOUDYY_FAIL_INSTALL_TARGET=str(self.zen / "cloudyy.cfg"),
        )

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(pref_target.read_text(), previous)
        self.assertFalse((self.zen / "cloudyy.cfg").exists())

    def _failing_install_bin(self) -> Path:
        fake_bin = self.root / "bin"
        fake_bin.mkdir(exist_ok=True)
        fake_install = fake_bin / "install"
        fake_install.write_text(
            "#!/usr/bin/env bash\n"
            'if [[ "${@: -1}" == "$CLOUDYY_FAIL_INSTALL_TARGET" ]]; then\n'
            "  exit 73\n"
            "fi\n"
            'exec /usr/bin/install "$@"\n'
        )
        fake_install.chmod(0o755)
        return fake_bin


if __name__ == "__main__":
    unittest.main()
