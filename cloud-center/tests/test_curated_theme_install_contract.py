"""Installer ownership contract for the curated theme cutover."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
RETIRE_SCRIPT = ROOT / "install/config/retire-legacy-matugen-link.sh"


class CuratedThemeInstallContractTests(unittest.TestCase):
    def test_package_manifest_and_schema_do_not_own_matugen_or_pywalfox(self):
        manifest = (ROOT / "install/packages/manifest.sh").read_text().lower()
        schema = (ROOT / "install/config/schema.sh").read_text().lower()

        self.assertNotIn('"matugen"', manifest)
        self.assertNotIn("python-pywalfox", manifest)
        self.assertNotIn("pywalfox", schema)

    def test_deploy_excludes_matugen_and_uses_curated_lifecycle(self):
        deploy = (ROOT / "install/config/deploy.sh").read_text()
        install = (ROOT / "install/install.sh").read_text()
        all_config = (ROOT / "install/config/all.sh").read_text()
        session = (ROOT / "bin/cloudyy-session-start").read_text()

        self.assertRegex(deploy, r'dirname" == "matugen"')
        self.assertIn("retire-legacy-matugen-link.sh", deploy)
        self.assertIn(
            'bash "${DEPLOY_SCRIPT_DIR}/retire-legacy-matugen-link.sh"', deploy
        )
        self.assertNotIn(
            'bash "${REPO_DIR}/install/config/retire-legacy-matugen-link.sh"', deploy
        )
        self.assertLess(
            deploy.index("retire-legacy-matugen-link.sh"), deploy.index("sync_repo\n")
        )
        self.assertNotIn("default-theme/matugen", deploy)
        self.assertNotIn(".config/matugen/generated", deploy)
        self.assertNotIn("pywalfox", deploy.lower())
        self.assertIn("cloudyy-theme bootstrap nord", install)
        self.assertIn('"$theme_ctl" bootstrap nord', all_config)
        self.assertIn("cloudyy-theme reconcile", session)
        self.assertNotIn("cloudyy-theme restore", install)
        self.assertNotIn("cloudyy-theme restore", all_config)

    def test_repository_no_longer_owns_matugen_runtime_configuration(self):
        self.assertFalse((ROOT / ".config/matugen").exists())
        self.assertFalse((ROOT / "install/assets/default-theme/matugen").exists())
        self.assertFalse((ROOT / "install/config/system-theme.sh").exists())

        active_files = [
            ROOT / "install/assets/defaults/.zshrc",
            ROOT / "bin/cloudyy-nvim-reload-theme",
            ROOT / "bin/cloudyy-session-start",
            ROOT / "bin/cloudyy-swayosd-restart",
            ROOT / ".config/nvim/lua/config/autocmds.lua",
        ]
        for path in active_files:
            with self.subTest(path=path):
                self.assertNotIn("matugen", path.read_text().lower())

    def test_owned_matugen_link_is_backed_up_and_detached(self):
        with tempfile.TemporaryDirectory(prefix="cloudyy-matugen-retire-") as temp:
            root = Path(temp)
            home = root / "home"
            repo = home / "cloudyy-linux"
            source = repo / ".config/matugen"
            source.mkdir(parents=True)
            (source / "generated").mkdir()
            (source / "generated/personal.txt").write_text("preserve me\n")
            config = home / ".config"
            config.mkdir()
            target = config / "matugen"
            target.symlink_to(source)
            backup = config / "cloudyy-backups/test"

            result = subprocess.run(
                [str(RETIRE_SCRIPT), str(repo), str(backup)],
                env=os.environ | {"HOME": str(home)},
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(target.exists())
            self.assertFalse(target.is_symlink())
            self.assertEqual(
                (backup / ".config/matugen/generated/personal.txt").read_text(),
                "preserve me\n",
            )

    def test_owned_link_backup_preserves_nested_symlinks(self):
        with tempfile.TemporaryDirectory(prefix="cloudyy-matugen-retire-") as temp:
            root = Path(temp)
            home = root / "home"
            repo = home / "cloudyy-linux"
            source = repo / ".config/matugen"
            source.mkdir(parents=True)
            outside = root / "outside.txt"
            outside.write_text("outside\n")
            (source / "external-link").symlink_to(outside)
            config = home / ".config"
            config.mkdir()
            (config / "matugen").symlink_to(source)
            backup = config / "cloudyy-backups/test"

            result = subprocess.run(
                [str(RETIRE_SCRIPT), str(repo), str(backup)],
                env=os.environ | {"HOME": str(home)},
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            copied_link = backup / ".config/matugen/external-link"
            self.assertTrue(copied_link.is_symlink())
            self.assertEqual(os.readlink(copied_link), str(outside))

    def test_non_repository_matugen_paths_are_untouched(self):
        with tempfile.TemporaryDirectory(prefix="cloudyy-matugen-retire-") as temp:
            root = Path(temp)
            home = root / "home"
            repo = home / "cloudyy-linux"
            config = home / ".config"
            config.mkdir(parents=True)
            backup = config / "cloudyy-backups/test"

            real_target = config / "matugen"
            real_target.mkdir()
            marker = real_target / "personal.txt"
            marker.write_text("mine\n")
            result = subprocess.run(
                [str(RETIRE_SCRIPT), str(repo), str(backup)],
                env=os.environ | {"HOME": str(home)},
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(marker.read_text(), "mine\n")
            self.assertFalse(backup.exists())


if __name__ == "__main__":
    unittest.main()
