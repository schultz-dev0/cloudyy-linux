"""Cloudyy curated theme engine — stage and read-only CLI contracts."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
THEME_COMMAND = REPO_ROOT / "bin" / "cloudyy-theme"
NORD_ROOT = REPO_ROOT / "themes" / "nord"
RECONCILE_ACTIONS = {
    "wallpaper", "compatibility-state", "link-boundary", "link-kitty", "link-gtk3",
    "link-gtk4", "link-wlogout", "link-btop", "link-starship",
    "link-hyprland", "migrate-hypr-modules", "link-zen", "link-obsidian", "chromium", "vscode",
    "retire-automode",
    "mode-gsettings", "mode-portal", "mode-qt", "mode-firefox", "mode-zen",
    "reload-hyprland", "reload-quickshell", "reload-kitty", "reload-nvim",
    "reload-btop", "reload-gtk", "reload-wlogout", "reload-starship",
    "reload-zen", "reload-obsidian", "reload-chromium",
}


class CuratedThemeEngineTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        root = Path(self.temporary_directory.name)
        self.home = root / "home"
        self.state = root / "state"
        self.config = root / "config"
        self.runtime = root / "runtime"
        self.fake_bin = root / "bin"
        self.zdotdir = self.config / "zsh"
        self.wallpaper_directory = self.home / "Wallpapers"
        self.wallpaper_log = root / "wallpaper.log"
        self.matugen_log = root / "matugen.log"
        self.integration_log = root / "integration.log"
        self.extra_environment: dict[str, str] = {}
        for directory in (
            self.home, self.state, self.config, self.runtime, self.fake_bin,
            self.wallpaper_directory,
        ):
            directory.mkdir()
        for command in (
            "awk", "bash", "cat", "chmod", "cmp", "cp", "cut", "dirname", "find",
            "flock", "grep", "identify", "jq", "ln", "mkdir", "mktemp", "mv",
            "python3", "readlink", "realpath", "rm", "sed", "sleep", "sort", "stat",
            "tail", "touch",
        ):
            target = shutil.which(command)
            self.assertIsNotNone(target, command)
            (self.fake_bin / command).symlink_to(target)
        (self.fake_bin / "pgrep").write_text("#!/usr/bin/env bash\nexit 1\n", encoding="utf-8")
        (self.fake_bin / "gsettings").write_text(
            "#!/usr/bin/env bash\n"
            "if [[ \"${1:-}\" == list-schemas ]]; then printf 'org.gnome.desktop.interface\\n'; fi\n"
            "if [[ \"${1:-}\" == list-keys ]]; then printf 'color-scheme\\n'; fi\n"
            "exit 0\n",
            encoding="utf-8",
        )
        for command in (
            "chromium", "hyprctl", "quickshell", "kitty", "nvim", "pkill", "thunar",
        ):
            (self.fake_bin / command).write_text(
                f"#!/usr/bin/env bash\nprintf '{command} %s\\n' \"$*\" >>\"$FAKE_INTEGRATION_LOG\"\nexit 0\n",
                encoding="utf-8",
            )
        for command in (
            "pgrep", "gsettings", "chromium", "hyprctl", "quickshell", "kitty",
            "nvim", "pkill", "thunar",
        ):
            (self.fake_bin / command).chmod(0o755)
        self.extra_environment |= {
            "PATH": str(self.fake_bin),
            "FAKE_INTEGRATION_LOG": str(self.integration_log),
        }

    def tearDown(self):
        self.temporary_directory.cleanup()

    def run_theme(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        environment = os.environ | {
            "HOME": str(self.home),
            "XDG_STATE_HOME": str(self.state),
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_RUNTIME_DIR": str(self.runtime),
            "ZDOTDIR": str(self.zdotdir),
            "CLOUDYY_WALLPAPER_DIR": str(self.wallpaper_directory),
        } | self.extra_environment
        return subprocess.run(
            [str(THEME_COMMAND), *arguments],
            check=False,
            cwd=REPO_ROOT,
            env=environment,
            text=True,
            capture_output=True,
        )

    def install_fake_wallpaper_backend(self, *, status: int = 0) -> None:
        required_commands = (
            "awk", "bash", "cat", "chmod", "cmp", "cp", "cut", "dirname", "find",
            "flock", "grep", "identify", "jq", "ln", "mkdir", "mktemp", "mv",
            "python3", "readlink", "realpath", "rm", "sed", "sleep", "sort", "stat",
            "tail", "touch",
        )
        for command in required_commands:
            target = shutil.which(command)
            self.assertIsNotNone(target, command)
            path = self.fake_bin / command
            if not path.exists():
                path.symlink_to(target)
        (self.fake_bin / "pgrep").write_text(
            "#!/usr/bin/env bash\n"
            "[[ \"$*\" == *Thunar* || \"$*\" == *thunar* ]] && exit 1\n"
            "exit 0\n",
            encoding="utf-8",
        )
        (self.fake_bin / "awww").write_text(
            "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$FAKE_WALLPAPER_LOG\"\n"
            "exit \"${FAKE_WALLPAPER_STATUS:-0}\"\n",
            encoding="utf-8",
        )
        (self.fake_bin / "awww-daemon").write_text(
            "#!/usr/bin/env bash\nprintf 'daemon\\n' >>\"$FAKE_WALLPAPER_LOG\"\n",
            encoding="utf-8",
        )
        (self.fake_bin / "matugen").write_text(
            "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$FAKE_MATUGEN_LOG\"\n",
            encoding="utf-8",
        )
        (self.fake_bin / "gsettings").write_text(
            "#!/usr/bin/env bash\n"
            "if [[ \"${1:-}\" == list-schemas ]]; then printf 'org.gnome.desktop.interface\\n'; fi\n"
            "if [[ \"${1:-}\" == list-keys ]]; then printf 'color-scheme\\n'; fi\n"
            "exit 0\n",
            encoding="utf-8",
        )
        for command in (
            "chromium", "hyprctl", "quickshell", "kitty", "nvim", "pkill", "thunar",
        ):
            (self.fake_bin / command).write_text(
                f"#!/usr/bin/env bash\nprintf '{command} %s\\n' \"$*\" >>\"$FAKE_INTEGRATION_LOG\"\nexit 0\n",
                encoding="utf-8",
            )
        for command in (
            "pgrep", "awww", "awww-daemon", "matugen", "gsettings", "hyprctl",
            "quickshell", "kitty", "nvim", "pkill", "chromium", "thunar",
        ):
            (self.fake_bin / command).chmod(0o755)
        self.extra_environment |= {
            "PATH": str(self.fake_bin),
            "FAKE_WALLPAPER_LOG": str(self.wallpaper_log),
            "FAKE_WALLPAPER_STATUS": str(status),
            "FAKE_MATUGEN_LOG": str(self.matugen_log),
            "FAKE_INTEGRATION_LOG": str(self.integration_log),
        }

    @property
    def compatibility_root(self) -> Path:
        return self.config / "hypr/theme_state"

    @property
    def active_stage_wallpaper(self) -> Path:
        return (self.state / "cloudyy/current").resolve() / "theme/wallpapers/1.jpg"

    def hide_wallpaper_backends(self) -> None:
        isolated_bin = Path(self.temporary_directory.name) / "isolated-bin"
        isolated_bin.mkdir()
        required_commands = (
            "bash", "cat", "chmod", "cmp", "cp", "dirname", "find", "flock",
            "identify", "jq", "ln", "mkdir", "mktemp", "mv", "python3", "readlink",
            "realpath", "rm", "sort", "stat",
        )
        for command in required_commands:
            target = shutil.which(command)
            self.assertIsNotNone(target, command)
            (isolated_bin / command).symlink_to(target)
        self.extra_environment["PATH"] = str(isolated_bin)

    def write_saved_wallpaper(self, wallpaper: Path, *, mode: str = "dark") -> None:
        current_directory = self.compatibility_root / "current_wallpaper"
        current_directory.mkdir(parents=True, exist_ok=True)
        (self.compatibility_root / "state.conf").write_text(
            f'THEME_MODE="{mode}"\nCURRENT_WALL="{wallpaper}"\n', encoding="utf-8"
        )
        (current_directory / "current.jpg").write_bytes(wallpaper.read_bytes())

    def run_theme_with_environment(self, environment: dict[str, str], *arguments: str) -> subprocess.CompletedProcess[str]:
        safe_environment = {
            "HOME": str(self.home),
            "XDG_STATE_HOME": str(self.state),
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_RUNTIME_DIR": str(self.runtime),
            "ZDOTDIR": str(self.zdotdir),
            "CLOUDYY_WALLPAPER_DIR": str(self.wallpaper_directory),
        } | environment
        return subprocess.run(
            [str(THEME_COMMAND), *arguments], check=False, cwd=REPO_ROOT,
            env=os.environ | safe_environment, text=True, capture_output=True,
        )

    def copy_nord_package(self) -> Path:
        destination = Path(tempfile.mkdtemp(dir=self.temporary_directory.name)) / "nord"
        shutil.copytree(NORD_ROOT, destination)
        return destination

    def run_validator(self, package: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "bash",
                "-c",
                'source lib/cloudyy-theme/common.sh; source lib/cloudyy-theme/package.sh; validate_theme_package "$1" nord',
                "_",
                str(package),
            ],
            check=False,
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
        )

    def run_library(self, program: str, *arguments: str) -> subprocess.CompletedProcess[str]:
        environment = os.environ | {
            "HOME": str(self.home),
            "XDG_STATE_HOME": str(self.state),
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_RUNTIME_DIR": str(self.runtime),
            "ZDOTDIR": str(self.zdotdir),
            "CLOUDYY_WALLPAPER_DIR": str(self.wallpaper_directory),
        } | self.extra_environment
        return subprocess.run(
            ["bash", "-c", program, "_", *arguments],
            check=False,
            cwd=REPO_ROOT,
            env=environment,
            text=True,
            capture_output=True,
        )

    def test_list_prints_shipped_slugs_in_lexical_order(self):
        # Doesn't assume Nord is the only shipped theme — themes/ is real,
        # user-populated content that grows over time, not a fixture.
        result = self.run_theme("list")

        self.assertEqual(result.returncode, 0, result.stderr)
        slugs = result.stdout.splitlines()
        self.assertIn("nord", slugs)
        self.assertEqual(slugs, sorted(slugs))

    def test_list_json_reports_shape_and_wallpaper_fallback_preview(self):
        # Doesn't assume Nord is the only shipped theme — see the note on
        # test_list_prints_shipped_slugs_in_lexical_order.
        result = self.run_theme("list", "--json")

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["current"], "")
        nords = [t for t in payload["themes"] if t["slug"] == "nord"]
        self.assertEqual(len(nords), 1)
        nord = nords[0]
        self.assertEqual(nord["name"], "Nord")
        self.assertEqual(nord["mode"], "dark")
        self.assertEqual(nord["colors"]["accent"], "#88C0D0")
        self.assertEqual(nord["preview"], str(NORD_ROOT / "wallpapers/1.jpg"))

    def test_list_json_reports_wallpapers_in_numeric_not_lexical_order(self):
        package = self.copy_nord_package()
        shutil.copy2(package / "wallpapers/1.jpg", package / "wallpapers/10.jpg")

        result = self.run_library(
            'source lib/cloudyy-theme/common.sh; source lib/cloudyy-theme/package.sh; '
            '_theme_wallpaper_paths "$1"',
            str(package),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        stems = [Path(line).stem for line in result.stdout.strip().splitlines()]
        self.assertEqual(stems, sorted(stems, key=int))
        self.assertEqual(stems[-1], "10")

    def test_list_json_reports_the_active_slug_once_prepared(self):
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)

        result = self.run_theme("list", "--json")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["current"], "nord")

    def test_theme_preview_path_prefers_a_shipped_preview_png_over_wallpaper_one(self):
        package = self.copy_nord_package()
        (package / "preview.png").write_bytes(b"not a real png, presence is what matters")

        result = self.run_library(
            'source lib/cloudyy-theme/common.sh; source lib/cloudyy-theme/package.sh; '
            '_theme_preview_path "$1"',
            str(package),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(package / "preview.png"))

    def test_unknown_and_path_traversal_slugs_are_validation_errors(self):
        for slug in ("missing", "../nord", "/tmp/nord"):
            with self.subTest(slug=slug):
                result = self.run_theme("prepare", slug)

                self.assertEqual(result.returncode, 10)

    def test_uninitialized_read_only_commands_do_not_invent_defaults(self):
        for command in ("current", "get-mode"):
            with self.subTest(command=command):
                result = self.run_theme(command)

                self.assertEqual(result.returncode, 3)
                self.assertEqual(result.stdout, "")
                self.assertIn("active theme", result.stderr.lower())

    def test_prepare_promotes_a_complete_private_stage(self):
        result = self.run_theme("prepare", "nord")

        self.assertEqual(result.returncode, 0, result.stderr)
        current = self.state / "cloudyy/current"
        self.assertTrue(current.is_symlink())
        self.assertEqual((current / "theme.name").read_text(), "nord\n")
        self.assertEqual((current / "wallpaper.index").read_text(), "1\n")
        self.assertEqual((current / "theme/theme.json").stat().st_mode & 0o777, 0o600)

    def test_prepare_never_writes_legacy_wallpaper_state(self):
        result = self.run_theme("prepare", "nord")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.compatibility_root.exists())

    def test_bootstrap_seeds_wallpaper_one_without_contacting_a_daemon(self):
        self.install_fake_wallpaper_backend()

        result = self.run_theme("bootstrap", "nord")

        self.assertEqual(result.returncode, 0, result.stderr)
        state = (self.compatibility_root / "state.conf").read_text(encoding="utf-8")
        self.assertEqual(
            state,
            f'THEME_MODE="dark"\nCURRENT_WALL="{self.active_stage_wallpaper}"\n',
        )
        self.assertEqual((self.compatibility_root / "state").read_text(), "0\n")
        self.assertEqual(
            (self.compatibility_root / "current_wallpaper/current.jpg").read_bytes(),
            self.active_stage_wallpaper.read_bytes(),
        )
        self.assertFalse(self.wallpaper_log.exists())

    def test_reconcile_preserves_a_valid_saved_wallpaper_override(self):
        self.install_fake_wallpaper_backend()
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        override = self.home / "override.png"
        override.write_bytes(b"user wallpaper")
        self.write_saved_wallpaper(override, mode="light")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"img {override}", self.wallpaper_log.read_text())
        self.assertEqual(
            (self.compatibility_root / "state.conf").read_text(),
            f'THEME_MODE="dark"\nCURRENT_WALL="{override}"\n',
        )

    def test_explicit_reconcile_selects_wallpaper_one(self):
        self.install_fake_wallpaper_backend()
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        override = self.home / "override.png"
        override.write_bytes(b"override")
        self.write_saved_wallpaper(override)

        result = self.run_theme("reconcile", "--apply-theme-wallpaper")

        self.assertEqual(result.returncode, 0, result.stderr)
        wallpaper = self.active_stage_wallpaper
        self.assertIn(f"img {wallpaper}", self.wallpaper_log.read_text())
        self.assertEqual(
            (self.compatibility_root / "state.conf").read_text(),
            f'THEME_MODE="dark"\nCURRENT_WALL="{wallpaper}"\n',
        )

    def test_use_selects_wallpaper_one(self):
        self.install_fake_wallpaper_backend()

        result = self.run_theme("use", "nord")

        self.assertEqual(result.returncode, 0, result.stderr)
        wallpaper = self.active_stage_wallpaper
        self.assertIn(f"img {wallpaper}", self.wallpaper_log.read_text())
        self.assertEqual(
            (self.compatibility_root / "state.conf").read_text(),
            f'THEME_MODE="dark"\nCURRENT_WALL="{wallpaper}"\n',
        )

    def test_saved_theme_wallpaper_keeps_its_stage_identity_across_promotion(self):
        self.install_fake_wallpaper_backend()
        self.assertEqual(self.run_theme("bootstrap", "nord").returncode, 0)
        first_wallpaper = self.active_stage_wallpaper
        first_bytes = first_wallpaper.read_bytes()
        self.assertIn(str(first_wallpaper), (self.compatibility_root / "state.conf").read_text())

        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        second_wallpaper = self.active_stage_wallpaper
        shutil.copyfile(second_wallpaper.with_name("2.jpg"), second_wallpaper)
        self.assertNotEqual(second_wallpaper.read_bytes(), first_bytes)

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"img {first_wallpaper}", self.wallpaper_log.read_text())
        self.assertNotIn(f"img {second_wallpaper}", self.wallpaper_log.read_text())
        self.assertEqual(
            (self.compatibility_root / "current_wallpaper/current.jpg").read_bytes(),
            first_bytes,
        )

    def test_failed_later_use_does_not_change_the_saved_wallpaper_identity(self):
        self.install_fake_wallpaper_backend()
        self.assertEqual(self.run_theme("use", "nord").returncode, 0)
        original_state = (self.compatibility_root / "state.conf").read_bytes()
        original_snapshot = (self.compatibility_root / "current_wallpaper/current.jpg").read_bytes()
        first_wallpaper = self.active_stage_wallpaper
        self.extra_environment["FAKE_WALLPAPER_STATUS"] = "8"

        result = self.run_theme("use", "nord")

        self.assertEqual(result.returncode, 20)
        self.assertEqual((self.compatibility_root / "state.conf").read_bytes(), original_state)
        self.assertEqual(
            (self.compatibility_root / "current_wallpaper/current.jpg").read_bytes(),
            original_snapshot,
        )
        self.assertIn(str(first_wallpaper), original_state.decode())
        self.assertEqual(first_wallpaper.read_bytes(), original_snapshot)

    def test_snapshot_fallback_survives_a_missing_saved_stage_asset(self):
        self.install_fake_wallpaper_backend()
        self.assertEqual(self.run_theme("use", "nord").returncode, 0)
        saved_wallpaper = self.active_stage_wallpaper
        saved_bytes = saved_wallpaper.read_bytes()
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        saved_wallpaper.unlink()
        self.wallpaper_log.unlink()

        result = self.run_theme("reconcile")

        snapshot = self.compatibility_root / "current_wallpaper/current.jpg"
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"img {snapshot}", self.wallpaper_log.read_text())
        self.assertEqual(snapshot.read_bytes(), saved_bytes)

    def test_failed_wallpaper_daemon_does_not_falsify_saved_state_and_records_later_skip(self):
        self.install_fake_wallpaper_backend(status=9)
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        override = self.home / "override.png"
        override.write_bytes(b"original wallpaper")
        self.write_saved_wallpaper(override)
        original_state = (self.compatibility_root / "state.conf").read_bytes()
        original_snapshot = (self.compatibility_root / "current_wallpaper/current.jpg").read_bytes()

        result = self.run_theme("reconcile", "--apply-theme-wallpaper")

        self.assertEqual(result.returncode, 20)
        self.assertEqual((self.compatibility_root / "state.conf").read_bytes(), original_state)
        self.assertEqual(
            (self.compatibility_root / "current_wallpaper/current.jpg").read_bytes(),
            original_snapshot,
        )
        activation = json.loads((self.state / "cloudyy/current/activation.json").read_text())
        self.assertEqual(activation["prepare"], {"status": "success"})
        self.assertEqual(activation["reconcile"]["status"], "failure")
        self.assertEqual(set(activation["reconcile"]["actions"]), RECONCILE_ACTIONS)
        self.assertEqual(
            activation["reconcile"]["actions"]["wallpaper"], {"status": "failure"}
        )
        self.assertEqual(
            activation["reconcile"]["actions"]["compatibility-state"], {"status": "skip"}
        )
        self.assertEqual(self.run_theme("current").stdout, "nord\n")
        self.assertEqual(self.run_theme("get-mode").stdout, "dark\n")

    def test_legacy_reconcile_documents_are_readable_and_upgraded_by_reconcile(self):
        for omitted in (
            {"migrate-hypr-modules"},
            {"migrate-hypr-modules", "retire-automode"},
        ):
            with self.subTest(omitted=omitted):
                self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
                activation_path = self.state / "cloudyy/current/activation.json"
                legacy_actions = {
                    action: {"status": "skip"}
                    for action in RECONCILE_ACTIONS - omitted
                }
                activation_path.write_text(json.dumps({
                    "prepare": {"status": "success"},
                    "reconcile": {"status": "success", "actions": legacy_actions},
                }) + "\n")

                self.assertEqual(self.run_theme("get-mode").stdout, "dark\n")
                reconciled = self.run_theme("reconcile")
                self.assertEqual(reconciled.returncode, 0, reconciled.stderr)
                upgraded = json.loads(activation_path.read_text())
                self.assertEqual(set(upgraded["reconcile"]["actions"]), RECONCILE_ACTIONS)

    def test_started_wallpaper_daemon_does_not_inherit_the_theme_lock(self):
        self.install_fake_wallpaper_backend()
        marker = Path(self.temporary_directory.name) / "daemon-started"
        self.extra_environment["FAKE_DAEMON_MARKER"] = str(marker)
        (self.fake_bin / "pgrep").write_text(
            '#!/usr/bin/env bash\n'
            '[[ "$*" == *awww-daemon* && -e "$FAKE_DAEMON_MARKER" ]]\n',
            encoding="utf-8",
        )
        (self.fake_bin / "awww-daemon").write_text(
            '#!/usr/bin/env bash\ntouch "$FAKE_DAEMON_MARKER"\nsleep 4\n', encoding="utf-8"
        )
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        self.assertEqual(self.run_theme("reconcile", "--apply-theme-wallpaper").returncode, 0)
        self.assertTrue(self.integration_log.is_relative_to(Path(self.temporary_directory.name)))
        integration_output = self.integration_log.read_text() if self.integration_log.exists() else ""
        for line in integration_output.splitlines():
            self.assertIn(
                line.split(maxsplit=1)[0],
                {"chromium", "hyprctl", "quickshell", "kitty", "nvim", "pkill", "thunar"},
            )

        started = time.monotonic()
        current = self.run_theme("current")

        self.assertEqual(current.returncode, 0, current.stderr)
        self.assertLess(time.monotonic() - started, 2)

    def test_reconcile_falls_back_to_wallpaper_one_when_saved_state_is_invalid(self):
        self.install_fake_wallpaper_backend()
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        self.compatibility_root.mkdir(parents=True)
        (self.compatibility_root / "state.conf").write_text(
            'THEME_MODE="light"\nCURRENT_WALL="/missing/wallpaper.jpg"\n', encoding="utf-8"
        )

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"img {self.active_stage_wallpaper}", self.wallpaper_log.read_text())

    def test_activation_record_failure_runs_later_action_and_preserves_prior_document(self):
        self.install_fake_wallpaper_backend()
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        activation = self.state / "cloudyy/current/activation.json"
        prior = activation.read_bytes()

        result = self.run_library(
            'source lib/cloudyy-theme/common.sh; source lib/cloudyy-theme/package.sh; '
            'source lib/cloudyy-theme/wallpaper.sh; source lib/cloudyy-theme/reconcile.sh; '
            'record_attempt=0; '
            '_activation_draft_write() { '
            'record_attempt=$((record_attempt + 1)); '
            'if [[ "$record_attempt" -eq 1 ]]; then return 1; fi; '
            '_activation_draft_write_impl "$@"; '
            '}; reconcile_theme true',
        )

        self.assertEqual(result.returncode, 20)
        self.assertEqual(activation.read_bytes(), prior)
        self.assertTrue((self.compatibility_root / "state.conf").is_file())

    def test_interrupted_activation_draft_leaves_prior_document_readable(self):
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        activation = self.state / "cloudyy/current/activation.json"
        prior = activation.read_bytes()

        interrupted = self.run_library(
            'source lib/cloudyy-theme/common.sh; source lib/cloudyy-theme/package.sh; '
            'source lib/cloudyy-theme/wallpaper.sh; source lib/cloudyy-theme/reconcile.sh; '
            'stage="$(active_stage)"; begin_activation_results "$stage"; '
            'write_activation_result wallpaper success',
        )

        self.assertEqual(interrupted.returncode, 0, interrupted.stderr)
        self.assertEqual(activation.read_bytes(), prior)
        self.assertEqual(self.run_theme("current").stdout, "nord\n")

    def test_exported_activation_draft_path_cannot_delete_an_arbitrary_file(self):
        self.install_fake_wallpaper_backend()
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        sentinel = Path(self.temporary_directory.name) / "sentinel"
        sentinel.write_text("keep\n", encoding="utf-8")
        self.extra_environment["CLOUDYY_ACTIVATION_DRAFT"] = str(sentinel)
        self.extra_environment["CLOUDYY_ACTIVATION_STAGE"] = str(sentinel.parent)

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(sentinel.is_file())
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep\n")

    def test_next_reconcile_prunes_only_owned_regular_activation_drafts(self):
        self.install_fake_wallpaper_backend()
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        state_root = self.state / "cloudyy"
        stale_draft = state_root / ".activation-draft.A1b2C3d4"
        stale_update = state_root / ".activation-draft-update.Z9y8X7w6"
        stale_draft.write_text("stale\n", encoding="utf-8")
        stale_update.write_text("stale\n", encoding="utf-8")
        sentinel = Path(self.temporary_directory.name) / "outside"
        sentinel.write_text("keep\n", encoding="utf-8")
        malicious_link = state_root / ".activation-draft.L1nK0001"
        malicious_link.symlink_to(sentinel)
        malicious_directory = state_root / ".activation-draft-update.D1r00001"
        malicious_directory.mkdir()
        unowned = state_root / ".activation-draft.bad-name"
        unowned.write_text("keep\n", encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(stale_draft.exists())
        self.assertFalse(stale_update.exists())
        self.assertTrue(malicious_link.is_symlink())
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep\n")
        self.assertTrue(malicious_directory.is_dir())
        self.assertEqual(unowned.read_text(encoding="utf-8"), "keep\n")

    def test_activation_finalization_failure_preserves_prior_complete_document(self):
        self.install_fake_wallpaper_backend()
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        activation = self.state / "cloudyy/current/activation.json"
        prior = activation.read_bytes()

        result = self.run_library(
            'source lib/cloudyy-theme/common.sh; source lib/cloudyy-theme/package.sh; '
            'source lib/cloudyy-theme/wallpaper.sh; source lib/cloudyy-theme/reconcile.sh; '
            '_commit_activation_draft() { return 1; }; reconcile_theme true',
        )

        self.assertEqual(result.returncode, 20)
        self.assertEqual(activation.read_bytes(), prior)
        self.assertTrue((self.compatibility_root / "state.conf").is_file())

    def test_recover_previous_swaps_retained_stages_and_reconciles(self):
        self.install_fake_wallpaper_backend()
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        first = (self.state / "cloudyy/current").resolve()
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        second = (self.state / "cloudyy/current").resolve()
        override = self.home / "override.png"
        override.write_bytes(b"override")
        self.write_saved_wallpaper(override)

        result = self.run_theme("recover-previous")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.state / "cloudyy/current").resolve(), first)
        self.assertEqual((self.state / "cloudyy/previous").resolve(), second)
        self.assertIn(f"img {override}", self.wallpaper_log.read_text())
        activation = json.loads((first / "activation.json").read_text())
        self.assertEqual(activation["reconcile"]["status"], "success")

    def test_recover_previous_rejects_absent_or_corrupt_retained_state_without_swapping(self):
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        current = self.state / "cloudyy/current"
        original = current.readlink()
        absent = self.run_theme("recover-previous")
        self.assertEqual(absent.returncode, 3)
        self.assertEqual(current.readlink(), original)

        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        previous = self.state / "cloudyy/previous"
        (previous / "activation.json").write_text("{}\n", encoding="utf-8")
        current_before_corruption = current.readlink()
        corrupt = self.run_theme("recover-previous")
        self.assertEqual(corrupt.returncode, 3)
        self.assertEqual(current.readlink(), current_before_corruption)

    def test_recover_previous_keeps_the_pointer_swap_on_partial_reconciliation(self):
        self.install_fake_wallpaper_backend(status=7)
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        first = (self.state / "cloudyy/current").resolve()
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        second = (self.state / "cloudyy/current").resolve()

        result = self.run_theme("recover-previous")

        self.assertEqual(result.returncode, 20)
        self.assertEqual((self.state / "cloudyy/current").resolve(), first)
        self.assertEqual((self.state / "cloudyy/previous").resolve(), second)
        activation = json.loads((first / "activation.json").read_text())
        self.assertEqual(activation["reconcile"]["status"], "failure")

    def test_transitional_wallpaper_commands_are_image_only_and_mode_commands_are_removed(self):
        self.install_fake_wallpaper_backend()
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        wallpapers = self.home / "Wallpapers/Dark"
        wallpapers.mkdir(parents=True)
        first = wallpapers / "a.jpg"
        second = wallpapers / "b.jpg"
        first.write_bytes(b"first")
        second.write_bytes(b"second")

        for command in (("set-image", str(first)), ("next",), ("random",), ("restore",)):
            with self.subTest(command=command):
                result = self.run_theme(*command)
                self.assertEqual(result.returncode, 0, result.stderr)

        self.assertFalse(self.matugen_log.exists())
        for command in (("toggle",), ("set", "--mode", "light"), ("refresh",)):
            with self.subTest(command=command):
                self.assertEqual(self.run_theme(*command).returncode, 2)

    def test_explicit_wallpaper_commands_fail_when_no_backend_is_available(self):
        self.assertEqual(self.run_theme("bootstrap", "nord").returncode, 0)
        wallpapers = self.home / "Wallpapers/Dark"
        wallpapers.mkdir(parents=True)
        wallpaper = wallpapers / "only.jpg"
        wallpaper.write_bytes(b"wallpaper")
        self.hide_wallpaper_backends()

        for command in (
            ("set-image", str(wallpaper)),
            ("next",),
            ("random",),
            ("restore",),
        ):
            with self.subTest(command=command):
                result = self.run_theme(*command)
                self.assertEqual(result.returncode, 20, result.stderr)

        reconcile = self.run_theme("reconcile")
        self.assertEqual(reconcile.returncode, 0, reconcile.stderr)
        activation = json.loads((self.state / "cloudyy/current/activation.json").read_text())
        actions = activation["reconcile"]["actions"]
        self.assertEqual(set(actions), RECONCILE_ACTIONS)
        self.assertEqual(actions["wallpaper"], {"status": "skip"})
        self.assertEqual(actions["compatibility-state"], {"status": "skip"})

    def test_tag_and_untag_keep_the_transitional_pool_contract(self):
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        wallpaper = self.home / "wall.jpg"
        wallpaper.write_bytes(b"wall")

        tagged = self.run_theme("tag", str(wallpaper), "light")
        link = self.home / "Wallpapers/Light/wall.jpg"
        self.assertEqual(tagged.returncode, 0, tagged.stderr)
        self.assertTrue(link.is_symlink())
        self.assertEqual(link.resolve(), wallpaper)

        untagged = self.run_theme("untag", str(wallpaper), "light")
        self.assertEqual(untagged.returncode, 0, untagged.stderr)
        self.assertFalse(link.exists())

    def test_prepare_preserves_a_valid_previous_stage_when_current_is_corrupt(self):
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        state_root = self.state / "cloudyy"
        current = state_root / "current"
        previous = state_root / "previous"
        previous.symlink_to(current.readlink())
        current.unlink()
        current.symlink_to("theme-stages/missing")

        result = self.run_theme("prepare", "nord")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(previous.is_symlink())
        self.assertEqual((previous / "theme.name").read_text(), "nord\n")

    def test_validator_rejects_duplicate_numeric_wallpaper_stems_across_extensions(self):
        package = self.copy_nord_package()
        shutil.copy(package / "wallpapers/1.jpg", package / "wallpapers/1.png")

        result = self.run_validator(package)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate wallpaper stem", result.stderr)

    def test_validator_rejects_non_color_application_content(self):
        package = self.copy_nord_package()
        (package / "applications/kitty.conf").write_text("font_size 14\n", encoding="utf-8")

        result = self.run_validator(package)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Kitty", result.stderr)

    def test_validator_accepts_optional_preview_png_but_not_other_stray_files(self):
        package = self.copy_nord_package()
        (package / "preview.png").write_bytes(b"stub png; presence is what the validator checks")

        self.assertEqual(self.run_validator(package).returncode, 0, self.run_validator(package).stderr)

        (package / "notes.txt").write_text("stray\n", encoding="utf-8")
        stray = self.run_validator(package)
        self.assertNotEqual(stray.returncode, 0)
        self.assertIn("unexpected package file: notes.txt", stray.stderr)

    def test_validator_rejects_symbolic_link_assets(self):
        package = self.copy_nord_package()
        asset = package / "applications/kitty.conf"
        asset.unlink()
        asset.symlink_to(package / "applications/gtk-3.css")

        result = self.run_validator(package)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symbolic links", result.stderr)

    def test_validator_parses_lua_without_executing_package_code(self):
        package = self.copy_nord_package()
        marker = Path(self.temporary_directory.name) / "executed"
        (package / "applications/nvim.lua").write_text(
            f'os.execute("touch {marker}")\nreturn {{}}\n', encoding="utf-8"
        )

        result = self.run_validator(package)

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(marker.exists())

    def test_current_rejects_invalid_activation_state_and_permissions(self):
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        current = self.state / "cloudyy/current"
        (current / "activation.json").write_text("{}\n", encoding="utf-8")

        invalid_state = self.run_theme("current")
        self.assertEqual(invalid_state.returncode, 3)

        (current / "activation.json").write_text(
            '{"prepare":{"status":"success"},"reconcile":{"status":"success",'
            '"actions":{"unowned":{"status":"success"}}}}\n',
            encoding="utf-8",
        )
        unowned_result = self.run_theme("current")
        self.assertEqual(unowned_result.returncode, 3)

        for actions in (
            {},
            {"wallpaper": {"status": "success"}},
            {"compatibility-state": {"status": "success"}},
        ):
            with self.subTest(actions=actions):
                (current / "activation.json").write_text(
                    json.dumps(
                        {
                            "prepare": {"status": "success"},
                            "reconcile": {"status": "success", "actions": actions},
                        }
                    ) + "\n",
                    encoding="utf-8",
                )
                partial_result = self.run_theme("current")
                self.assertEqual(partial_result.returncode, 3)

        (current / "activation.json").write_text('{"prepare":{"status":"success"}}\n', encoding="utf-8")
        (current / "theme/theme.json").chmod(0o644)
        invalid_permissions = self.run_theme("get-mode")
        self.assertEqual(invalid_permissions.returncode, 3)

    def test_prepare_normalizes_lock_setup_and_promotion_failures(self):
        self.runtime.rmdir()
        self.runtime.write_text("not a directory\n", encoding="utf-8")
        self.state.rmdir()
        self.state.write_text("not a directory\n", encoding="utf-8")

        lock_failure = self.run_theme("prepare", "nord")
        self.assertEqual(lock_failure.returncode, 11)

        self.state.unlink()
        self.state.mkdir()
        blocked_current = self.state / "cloudyy/current"
        blocked_current.mkdir(parents=True)
        (blocked_current / "keep").write_text("keep\n", encoding="utf-8")

        promotion_failure = self.run_theme("prepare", "nord")
        self.assertEqual(promotion_failure.returncode, 12)
        self.assertEqual((blocked_current / "keep").read_text(), "keep\n")

    def test_theme_lock_symlinks_are_rejected_without_touching_their_targets(self):
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        sentinel = Path(self.temporary_directory.name) / "lock-target"
        sentinel.write_text("safe\n", encoding="utf-8")
        runtime_lock = self.runtime / "cloudyy-theme.lock"
        runtime_lock.unlink()
        runtime_lock.symlink_to(sentinel)

        runtime_result = self.run_theme("prepare", "nord")

        self.assertEqual(runtime_result.returncode, 11)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "safe\n")
        read_result = self.run_theme("current")
        self.assertEqual(read_result.returncode, 3)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "safe\n")

        runtime_lock.unlink()
        bad_runtime = Path(self.temporary_directory.name) / "bad-runtime"
        bad_runtime.write_text("not a directory\n", encoding="utf-8")
        state_root = self.state / "cloudyy"
        (state_root / "theme.lock").symlink_to(sentinel)
        environment = {
            "HOME": str(self.home), "XDG_STATE_HOME": str(self.state),
            "XDG_CONFIG_HOME": str(self.config), "XDG_RUNTIME_DIR": str(bad_runtime),
        }

        fallback_result = self.run_theme_with_environment(environment, "prepare", "nord")

        self.assertEqual(fallback_result.returncode, 11)
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "safe\n")

    def test_prepare_maps_corrupt_previous_replacement_to_promotion_failure(self):
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        state_root = self.state / "cloudyy"
        (state_root / "current").unlink()
        (state_root / "current").symlink_to("theme-stages/missing")
        (state_root / "previous").mkdir()

        result = self.run_theme("prepare", "nord")

        self.assertEqual(result.returncode, 12)
        self.assertTrue((state_root / "previous").is_dir())

    def test_prepare_creates_complete_private_state_and_prunes_stale_stages(self):
        for _ in range(3):
            result = self.run_theme("prepare", "nord")
            self.assertEqual(result.returncode, 0, result.stderr)

        state_root = self.state / "cloudyy"
        stages = sorted((state_root / "theme-stages").iterdir())
        self.assertEqual(len(stages), 2)
        self.assertEqual({stage.name.startswith("stage.") for stage in stages}, {True})
        self.assertEqual((state_root / "current/activation.json").read_text(), '{"prepare":{"status":"success"}}\n')
        for stage in stages:
            for path in stage.rglob("*"):
                expected_mode = 0o700 if path.is_dir() else 0o600
                self.assertEqual(path.stat().st_mode & 0o777, expected_mode, path)

    def test_prepare_canonicalizes_a_symlinked_state_parent_without_pruning_current(self):
        real_state = Path(self.temporary_directory.name) / "real-state"
        real_state.mkdir()
        self.state.rmdir()
        self.state.symlink_to(real_state, target_is_directory=True)

        for _ in range(3):
            result = self.run_theme("prepare", "nord")
            self.assertEqual(result.returncode, 0, result.stderr)

        current = real_state / "cloudyy/current"
        self.assertTrue(current.is_symlink())
        self.assertEqual((current / "theme.name").read_text(), "nord\n")

    def test_prepare_rejects_state_and_stage_root_symlinks_without_following_them(self):
        outside = Path(self.temporary_directory.name) / "outside"
        outside.mkdir()
        sentinel = outside / "sentinel"
        sentinel.write_text("safe\n", encoding="utf-8")
        state_root = self.state / "cloudyy"
        state_root.symlink_to(outside, target_is_directory=True)

        state_link = self.run_theme("prepare", "nord")
        self.assertEqual(state_link.returncode, 11)
        self.assertEqual(sentinel.read_text(), "safe\n")

        state_root.unlink()
        state_root.mkdir()
        (state_root / "theme-stages").symlink_to(outside, target_is_directory=True)
        stages_link = self.run_theme("prepare", "nord")
        self.assertEqual(stages_link.returncode, 11)
        self.assertEqual(sentinel.read_text(), "safe\n")

    def test_promote_rejects_a_valid_stage_outside_the_canonical_stage_root(self):
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        external = Path(self.temporary_directory.name) / "external-stage"
        shutil.copytree(self.state / "cloudyy/current", external, symlinks=True)
        for path in external.rglob("*"):
            path.chmod(0o700 if path.is_dir() else 0o600)
        external.chmod(0o700)

        result = self.run_library(
            'source lib/cloudyy-theme/common.sh; source lib/cloudyy-theme/package.sh; promote_stage "$1"',
            str(external),
        )

        self.assertEqual(result.returncode, 12)

    def test_current_rejects_extra_top_level_stage_entries(self):
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        (self.state / "cloudyy/current/unowned").write_text("no\n", encoding="utf-8")

        result = self.run_theme("current")

        self.assertEqual(result.returncode, 3)

    def test_static_lua_validator_rejects_expression_bypasses_and_accepts_generic_identifiers(self):
        lua_path = Path(self.temporary_directory.name) / "theme.lua"
        palette = ",\n    ".join(f"shade{i} = \"#112233\"" for i in range(2))
        lua_path.write_text(
            f'return {{\n  name = "Generic",\n  mode = "dark",\n  palette = {{\n    {palette},\n  }},\n'
            '  highlights = { Normal = { fg = "shade1", bg = "shade0" } },\n}\n',
            encoding="utf-8",
        )
        valid = subprocess.run(
            ["python3", "-c", "import sys; from pathlib import Path; sys.path.insert(0, 'lib/cloudyy-theme'); from validate_assets import validate_lua; validate_lua(Path(sys.argv[1]), 'Generic', 'dark')", str(lua_path)],
            check=False,
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
        )
        self.assertEqual(valid.returncode, 0, valid.stderr)

        lua_path.write_text(
            lua_path.read_text(encoding="utf-8").replace('highlights = {', 'escape = _G["run"],\n  highlights = {'),
            encoding="utf-8",
        )
        bypass = subprocess.run(
            ["python3", "-c", "import sys; from pathlib import Path; sys.path.insert(0, 'lib/cloudyy-theme'); from validate_assets import validate_lua; validate_lua(Path(sys.argv[1]), 'Generic', 'dark')", str(lua_path)],
            check=False,
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(bypass.returncode, 0)

        lua_path.write_text('return { name = "Generic", mode = "dark", palette = {}, highlights = { Normal = { fg = "shade0" } } }\n', encoding="utf-8")
        empty = subprocess.run(
            ["python3", "-c", "import sys; from pathlib import Path; sys.path.insert(0, 'lib/cloudyy-theme'); from validate_assets import validate_lua; validate_lua(Path(sys.argv[1]), 'Generic', 'dark')", str(lua_path)],
            check=False, cwd=REPO_ROOT, text=True, capture_output=True,
        )
        self.assertNotEqual(empty.returncode, 0)

    def test_fallback_lock_and_active_reads_reject_state_symlinks_without_touching_target(self):
        outside = Path(self.temporary_directory.name) / "outside"
        outside.mkdir()
        sentinel = outside / "sentinel"
        sentinel.write_text("safe\n", encoding="utf-8")
        (self.state / "cloudyy").symlink_to(outside, target_is_directory=True)
        bad_runtime = Path(self.temporary_directory.name) / "bad-runtime"
        bad_runtime.write_text("not a directory\n", encoding="utf-8")
        environment = {
            "HOME": str(self.home), "XDG_STATE_HOME": str(self.state),
            "XDG_CONFIG_HOME": str(self.config), "XDG_RUNTIME_DIR": str(bad_runtime),
        }

        prepare = self.run_theme_with_environment(environment, "prepare", "nord")
        self.assertEqual(prepare.returncode, 11)
        self.assertFalse((outside / "theme.lock").exists())
        self.assertEqual(sentinel.read_text(), "safe\n")
        for command in ("current", "get-mode"):
            result = self.run_theme_with_environment(environment, command)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(result.stdout, "")

    def test_current_rejects_temporary_stage_pointer(self):
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        current = self.state / "cloudyy/current"
        stage = current.resolve()
        temporary = stage.with_name(".tmp.pointer")
        stage.rename(temporary)
        current.unlink()
        current.symlink_to(f"theme-stages/{temporary.name}")

        result = self.run_theme("current")

        self.assertEqual(result.returncode, 3)

    def test_cleanup_reports_injected_deletion_failure(self):
        stages = self.state / "cloudyy/theme-stages"
        stages.mkdir(parents=True)
        (stages / ".tmp.failed").mkdir()
        result = self.run_library(
            'source lib/cloudyy-theme/common.sh; source lib/cloudyy-theme/package.sh; _remove_stage_directory() { return 1; }; _cleanup_stages',
        )

        self.assertNotEqual(result.returncode, 0)

    def test_promotion_cleanup_failure_preserves_exit_twelve(self):
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        state_root = self.state / "cloudyy"
        previous = state_root / "previous"
        previous.mkdir()
        (previous / "keep").write_text("safe\n", encoding="utf-8")
        stage = (state_root / "current").resolve()

        result = self.run_library(
            'set -e; source lib/cloudyy-theme/common.sh; source lib/cloudyy-theme/package.sh; '
            'rm() { return 1; }; promote_stage "$1"',
            str(stage),
        )

        self.assertEqual(result.returncode, 12)

    def test_validator_reports_non_object_json_without_traceback(self):
        cases = (
            ("applications/vscode.json", "[]\n"),
            ("applications/chromium/manifest.json", "[]\n"),
            (
                "applications/chromium/manifest.json",
                '{"name":"Cloudyy Nord","version":"1.0.0","manifest_version":3,"theme":null}\n',
            ),
        )
        for relative, payload in cases:
            with self.subTest(relative=relative, payload=payload):
                package = self.copy_nord_package()
                (package / relative).write_text(payload, encoding="utf-8")
                result = self.run_validator(package)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cloudyy-theme:", result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    def test_current_serializes_behind_the_theme_lock_without_changing_output(self):
        self.assertEqual(self.run_theme("prepare", "nord").returncode, 0)
        lock_path = self.runtime / "cloudyy-theme.lock"
        holder = subprocess.Popen(
            ["bash", "-c", 'exec 9>"$1"; flock -x 9; read -r || true', "_", str(lock_path)],
            stdin=subprocess.PIPE,
            text=True,
        )
        try:
            time.sleep(0.1)
            reader = subprocess.Popen(
                [str(THEME_COMMAND), "current"], cwd=REPO_ROOT,
                env=os.environ | {"HOME": str(self.home), "XDG_STATE_HOME": str(self.state), "XDG_CONFIG_HOME": str(self.config), "XDG_RUNTIME_DIR": str(self.runtime)},
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            time.sleep(0.1)
            self.assertIsNone(reader.poll())
            holder.stdin.close()
            self.assertEqual(holder.wait(timeout=5), 0)
            stdout, stderr = reader.communicate(timeout=5)
        finally:
            if holder.poll() is None:
                holder.kill()

        self.assertEqual(reader.returncode, 0, stderr)
        self.assertEqual(stdout, "nord\n")


if __name__ == "__main__":
    unittest.main()
