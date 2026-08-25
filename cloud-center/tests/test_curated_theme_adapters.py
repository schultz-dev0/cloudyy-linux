"""Cloudyy curated theme adapters — safe merge, link, mode, and reload contracts."""

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
CODE_UPDATER = REPO_ROOT / "bin" / "cloudyy-code-update-vscodium"

LEGACY_HYPR_COLORS = """-- Hyprland theme tokens from matugen (generated hyprcolors.conf).
-- Source: ~/.config/matugen/generated/hyprcolors.conf

local M = {}

local path = os.getenv("HOME") .. "/.config/matugen/generated/hyprcolors.conf"
local f = io.open(path, "r")
if f then
\tfor line in f:lines() do
\t\tlocal name, value = line:match("^%$([%w_]+)%s*=%s*(.-)%s*$")
\t\tif name and value and value ~= "" then
\t\t\tM[name] = value
\t\tend
\tend
\tf:close()
end

M.primary = M.primary or "rgba(88c0d0ff)"
M.inverse_on_surface = M.inverse_on_surface or "rgba(595959aa)"

return M
"""


class CuratedThemeAdaptersTest(unittest.TestCase):
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
        self.command_log = root / "commands.log"
        for directory in (
            self.home, self.state, self.config, self.runtime, self.fake_bin,
            self.wallpaper_directory,
        ):
            directory.mkdir()
        for command in (
            "awk", "bash", "cat", "chmod", "cmp", "cp", "cut", "dirname", "find",
            "flock", "grep", "identify", "jq", "ln", "mkdir", "mktemp", "mv",
            "python3", "readlink", "realpath", "rm", "sed", "sort", "stat", "tail",
            "rmdir", "sleep", "touch",
        ):
            target = shutil.which(command)
            self.assertIsNotNone(target, command)
            (self.fake_bin / command).symlink_to(target)
        self.environment = os.environ | {
            "HOME": str(self.home),
            "XDG_STATE_HOME": str(self.state),
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_RUNTIME_DIR": str(self.runtime),
            "ZDOTDIR": str(self.zdotdir),
            "CLOUDYY_WALLPAPER_DIR": str(self.wallpaper_directory),
            "PATH": str(self.fake_bin),
            "CLOUDYY_TEST_COMMAND_LOG": str(self.command_log),
        }
        self._write_fake("pgrep", "[[ \"$*\" == *awww-daemon* ]]")
        self._write_fake("awww", "exit 0")
        self._write_fake("awww-daemon", "exit 0")
        for command in (
            "chromium", "hyprctl", "quickshell", "kitty", "nvim", "pkill", "thunar",
        ):
            self._write_fake(
                command,
                f"printf '{command} %s\\n' \"$*\" >>\"$CLOUDYY_TEST_COMMAND_LOG\"\nexit 0",
            )
        self._write_fake(
            "gsettings",
            "printf 'gsettings %s\\n' \"$*\" >>\"$CLOUDYY_TEST_COMMAND_LOG\"\n"
            "if [[ \"${1:-}\" == list-schemas ]]; then printf 'org.gnome.desktop.interface\\n'; fi\n"
            "if [[ \"${1:-}\" == list-keys ]]; then "
            "printf 'color-scheme\\ngtk-application-prefer-dark-mode\\n'; fi\n"
            "exit 0",
        )

    def tearDown(self):
        self.temporary_directory.cleanup()

    def _write_fake(self, name: str, body: str) -> Path:
        path = self.fake_bin / name
        path.write_text(f"#!/usr/bin/env bash\n{body}\n", encoding="utf-8")
        path.chmod(0o755)
        return path

    def run_theme(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(THEME_COMMAND), *arguments], cwd=REPO_ROOT, env=self.environment,
            text=True, capture_output=True, check=False,
        )

    def run_adapter(self, function: str, *arguments: str) -> subprocess.CompletedProcess[str]:
        program = (
            "source lib/cloudyy-theme/common.sh; "
            "source lib/cloudyy-theme/package.sh; "
            "source lib/cloudyy-theme/adapters.sh; "
            f"{function} \"$@\""
        )
        return subprocess.run(
            ["bash", "-c", program, "_", *arguments], cwd=REPO_ROOT,
            env=self.environment, text=True, capture_output=True, check=False,
        )

    def prepare(self) -> Path:
        result = self.run_theme("prepare", "nord")
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.state / "cloudyy/current/theme"

    def _create_consumer_roots(self) -> None:
        for relative in (
            "kitty", "gtk-3.0", "gtk-4.0", "wlogout", "btop/themes", "zsh",
            "hypr", "chromium", "Code/User", "Code - OSS/User",
            "VSCodium/User", "Cursor/User", "qt6ct", "cloudyy",
        ):
            (self.config / relative).mkdir(parents=True, exist_ok=True)

    def _create_profiles_and_vault(self) -> tuple[Path, Path, Path]:
        firefox_profile = self.home / ".mozilla/firefox/profile.default"
        firefox_profile.mkdir(parents=True)
        firefox_ini = self.home / ".mozilla/firefox/profiles.ini"
        firefox_ini.write_text(
            "[Profile0]\nName=default\nIsRelative=1\nPath=profile.default\n", encoding="utf-8"
        )
        zen_profile = self.config / "zen/profile.default"
        zen_profile.mkdir(parents=True)
        (self.config / "zen/profiles.ini").write_text(
            "[Profile0]\nIsRelative=1\nPath=profile.default\n", encoding="utf-8"
        )
        vault = self.home / "Notes/.obsidian"
        vault.mkdir(parents=True)
        return firefox_profile, zen_profile, vault

    def expected_links(self, theme: Path, zen_profile: Path, vault: Path) -> dict[Path, Path]:
        applications = theme / "applications"
        return {
            self.config / "cloudyy/current-theme": theme,
            self.config / "kitty/current-theme.conf": applications / "kitty.conf",
            self.config / "gtk-3.0/cloudyy-theme.css": applications / "gtk-3.css",
            self.config / "gtk-4.0/cloudyy-theme.css": applications / "gtk-4.css",
            self.config / "wlogout/cloudyy-theme.css": applications / "wlogout.css",
            self.config / "btop/themes/cloudyy.theme": applications / "btop.theme",
            self.config / "hypr/cloudyy-theme.conf": applications / "hyprland.conf",
            zen_profile / "chrome/cloudyy-theme.css": applications / "zen.css",
            vault / "snippets/cloudyy-theme.css": applications / "obsidian.css",
        }

    def legacy_links(self, zen_profile: Path, vault: Path) -> dict[Path, Path]:
        generated = self.config / "matugen/generated"
        return {
            self.config / "cloudyy/current-theme": generated,
            self.config / "kitty/current-theme.conf": generated / "kitty-colors.conf",
            self.config / "gtk-3.0/cloudyy-theme.css": generated / "gtk-3.css",
            self.config / "gtk-4.0/cloudyy-theme.css": generated / "gtk-4.css",
            self.config / "wlogout/cloudyy-theme.css": generated / "colors.css",
            self.config / "btop/themes/cloudyy.theme": generated / "btop.theme",
            self.config / "hypr/cloudyy-theme.conf": generated / "hyprcolors.conf",
        }

    def test_stable_links_are_created_through_current_and_rerun_is_idempotent(self):
        theme = self.prepare()
        self._create_consumer_roots()
        _, zen_profile, vault = self._create_profiles_and_vault()

        first = self.run_theme("reconcile")
        self.assertEqual(first.returncode, 0, first.stderr)
        before = {path: os.readlink(path) for path in self.expected_links(theme, zen_profile, vault)}
        second = self.run_theme("reconcile")

        self.assertEqual(second.returncode, 0, second.stderr)
        stable_root = self.state / "cloudyy/current/theme"
        for path, target in self.expected_links(theme, zen_profile, vault).items():
            with self.subTest(path=path):
                self.assertTrue(path.is_symlink())
                self.assertEqual(path.resolve(), target.resolve())
                self.assertIn(str(stable_root), os.readlink(path))
                self.assertEqual(os.readlink(path), before[path])
                self.assertNotIn("theme-stages", os.readlink(path))

    def test_gtk_adapters_install_one_owned_import_and_preserve_existing_css(self):
        self.prepare()
        self._create_consumer_roots()
        gtk3 = self.config / "gtk-3.0/gtk.css"
        gtk4 = self.config / "gtk-4.0/gtk.css"
        gtk3.write_text("/* personal gtk3 */\nwindow { padding: 1px; }\n")

        first = self.run_theme("reconcile")
        self.assertEqual(first.returncode, 0, first.stderr)
        before = {gtk3: gtk3.read_bytes(), gtk4: gtk4.read_bytes()}
        second = self.run_theme("reconcile")
        self.assertEqual(second.returncode, 0, second.stderr)

        marker = "/* >>> cloudyy-theme import >>> */"
        import_line = '@import url("cloudyy-theme.css");'
        for path in (gtk3, gtk4):
            with self.subTest(path=path):
                content = path.read_text()
                self.assertEqual(content.count(marker), 1)
                self.assertEqual(content.count(import_line), 1)
                self.assertEqual(path.read_bytes(), before[path])
        self.assertTrue(gtk3.read_text().startswith("/* personal gtk3 */\nwindow"))

    def test_gtk_adapter_removes_and_backs_up_real_legacy_matugen_import(self):
        theme = self.prepare()
        directory = self.config / "gtk-3.0"
        directory.mkdir(parents=True)
        gtk_css = directory / "gtk.css"
        original = '/* personal preamble */\n@import url("../matugen/generated/gtk-3.css");\n'
        gtk_css.write_text(original)

        first = self.run_adapter("adapter_gtk3", str(theme))
        self.assertEqual(first.returncode, 0, first.stderr)

        content = gtk_css.read_text()
        self.assertNotIn('@import url("../matugen/generated/gtk-3.css");', content)
        self.assertTrue(content.startswith("/* personal preamble */"))
        self.assertEqual(content.count("/* >>> cloudyy-theme import >>> */"), 1)
        self.assertEqual(content.count('@import url("cloudyy-theme.css");'), 1)
        backup = Path(f"{gtk_css}.cloudyy-legacy-backup")
        self.assertTrue(backup.is_file())
        self.assertEqual(backup.read_text(), original)

        # Idempotent rerun: the Cloudyy marker already present, nothing changes further.
        second = self.run_adapter("adapter_gtk3", str(theme))
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(gtk_css.read_text(), content)
        self.assertEqual(backup.read_text(), original)

    def test_gtk_adapter_preserves_unrecognized_legacy_import_variant_and_warns(self):
        theme = self.prepare()
        directory = self.config / "gtk-4.0"
        directory.mkdir(parents=True)
        gtk_css = directory / "gtk.css"
        # Single-quoted variant: looks like a Matugen GTK import but doesn't
        # exactly match the fingerprint Matugen's gtk4 template actually emits.
        original = "@import url('../matugen/generated/gtk-4.css');\n"
        gtk_css.write_text(original)

        result = self.run_adapter("adapter_gtk4", str(theme))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("legacy Matugen GTK import was not removed", result.stderr)
        self.assertIn(str(gtk_css), result.stderr)
        content = gtk_css.read_text()
        self.assertTrue(content.startswith(original))
        self.assertEqual(content.count("/* >>> cloudyy-theme import >>> */"), 1)
        self.assertFalse(Path(f"{gtk_css}.cloudyy-legacy-backup").exists())

        # Idempotent rerun: marker already present, no further changes or duplicate blocks.
        second = self.run_adapter("adapter_gtk4", str(theme))
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(gtk_css.read_text(), content)

    def test_gtk_adapters_create_missing_fresh_install_directories(self):
        theme = self.prepare()

        for function, version, payload in (
            ("adapter_gtk3", "3.0", "gtk-3.css"),
            ("adapter_gtk4", "4.0", "gtk-4.css"),
        ):
            with self.subTest(version=version):
                directory = self.config / f"gtk-{version}"
                self.assertFalse(directory.exists())

                result = self.run_adapter(function, str(theme))

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    (directory / "cloudyy-theme.css").resolve(),
                    (theme / "applications" / payload).resolve(),
                )
                self.assertEqual(
                    (directory / "gtk.css").read_text(),
                    "/* >>> cloudyy-theme import >>> */\n"
                    '@import url("cloudyy-theme.css");\n'
                    "/* <<< cloudyy-theme import <<< */\n",
                )

    def test_gtk_adapter_rejects_ambiguous_import_without_creating_theme_link(self):
        self.prepare()
        directory = self.config / "gtk-3.0"
        directory.mkdir(parents=True)
        gtk_css = directory / "gtk.css"
        original = (
            "/* >>> cloudyy-theme import >>> */\n"
            '@import url("cloudyy-theme.css");\n'
            "/* personal text where the owned end marker should be */\n"
        )
        gtk_css.write_text(original)

        result = self.run_adapter("adapter_gtk3", str(self.state / "cloudyy/current/theme"))

        self.assertEqual(result.returncode, 1)
        self.assertEqual(gtk_css.read_text(), original)
        self.assertFalse((directory / "cloudyy-theme.css").exists())

    def test_gtk_adapter_rejects_extra_import_outside_valid_owned_block(self):
        self.prepare()
        directory = self.config / "gtk-3.0"
        directory.mkdir(parents=True)
        gtk_css = directory / "gtk.css"
        original = (
            '@import url("cloudyy-theme.css");\n'
            "/* >>> cloudyy-theme import >>> */\n"
            '@import url("cloudyy-theme.css");\n'
            "/* <<< cloudyy-theme import <<< */\n"
        )
        gtk_css.write_text(original)

        result = self.run_adapter("adapter_gtk3", str(self.state / "cloudyy/current/theme"))

        self.assertEqual(result.returncode, 1)
        self.assertEqual(gtk_css.read_text(), original)
        self.assertFalse((directory / "cloudyy-theme.css").exists())

    def test_gtk_adapter_rolls_back_new_link_when_atomic_import_write_fails(self):
        theme = self.prepare()
        directory = self.config / "gtk-3.0"
        directory.mkdir(parents=True)
        gtk_css = directory / "gtk.css"
        original = "/* personal */\n"
        gtk_css.write_text(original)
        program = (
            "source lib/cloudyy-theme/common.sh; "
            "source lib/cloudyy-theme/package.sh; "
            "source lib/cloudyy-theme/adapters.sh; "
            "_atomic_replace_from() { return 1; }; "
            "adapter_gtk3 \"$1\""
        )

        result = subprocess.run(
            ["bash", "-c", program, "_", str(theme)], cwd=REPO_ROOT,
            env=self.environment, text=True, capture_output=True, check=False,
        )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(gtk_css.read_text(), original)
        self.assertFalse((directory / "cloudyy-theme.css").exists())

    def test_gtk_adapter_removes_fresh_directory_when_link_install_fails(self):
        theme = self.prepare()
        directory = self.config / "gtk-3.0"
        program = (
            "source lib/cloudyy-theme/common.sh; "
            "source lib/cloudyy-theme/package.sh; "
            "source lib/cloudyy-theme/adapters.sh; "
            "_install_stable_link() { return 1; }; "
            "adapter_gtk3 \"$1\""
        )

        result = subprocess.run(
            ["bash", "-c", program, "_", str(theme)], cwd=REPO_ROOT,
            env=self.environment, text=True, capture_output=True, check=False,
        )

        self.assertEqual(result.returncode, 1)
        self.assertFalse(directory.exists())

    def test_hypr_module_migration_rewrites_only_owned_legacy_fragments(self):
        theme = self.prepare()
        hypr = self.config / "hypr"
        hypr.mkdir()
        colors = hypr / "colors.lua"
        look = hypr / "lookandfeel.lua"
        bindings = hypr / "bindings.lua"
        legacy_look = (
            "before = true\n"
            "\t\t\tactive_border = colors.primary,\n"
            "\t\t\tinactive_border = colors.inverse_on_surface,\n"
            "after = true\n"
        )
        legacy_bindings = (
            "before()\n"
            "-- ── Appearance ───────────────────────────────────────────────\n\n"
            'hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("cloudyy-theme toggle"), '
            '{ desc = "Toggle light/dark theme" })\n\n'
            "after()\n"
        )
        colors.write_text(LEGACY_HYPR_COLORS, encoding="utf-8")
        look.write_text(legacy_look, encoding="utf-8")
        bindings.write_text(legacy_bindings, encoding="utf-8")

        result = self.run_adapter("adapter_hypr_modules", str(theme))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            colors.read_bytes(),
            (REPO_ROOT / "install/assets/defaults/hypr/colors.lua").read_bytes(),
        )
        self.assertEqual(
            look.read_text(),
            legacy_look.replace("colors.primary", "colors.accent").replace(
                "colors.inverse_on_surface", "colors.border"
            ),
        )
        self.assertEqual(bindings.read_text(), "before()\nafter()\n")
        for path, original in (
            (colors, LEGACY_HYPR_COLORS),
            (look, legacy_look),
            (bindings, legacy_bindings),
        ):
            self.assertEqual(
                Path(f"{path}.cloudyy-legacy-backup").read_text(), original
            )

        second = self.run_adapter("adapter_hypr_modules", str(theme))
        self.assertEqual(second.returncode, 0, second.stderr)

    def test_hypr_module_migration_preserves_every_file_on_ambiguous_legacy_input(self):
        theme = self.prepare()
        hypr = self.config / "hypr"
        hypr.mkdir()
        colors = hypr / "colors.lua"
        look = hypr / "lookandfeel.lua"
        bindings = hypr / "bindings.lua"
        originals = {
            colors: LEGACY_HYPR_COLORS.replace("local M = {}", "local M = { personal = true }"),
            look: "active_border = colors.primary,\ninactive_border = colors.inverse_on_surface,\n",
            bindings: 'hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("cloudyy-theme toggle"))\n',
        }
        for path, content in originals.items():
            path.write_text(content, encoding="utf-8")

        result = self.run_adapter("adapter_hypr_modules", str(theme))

        self.assertEqual(result.returncode, 1)
        for path, content in originals.items():
            self.assertEqual(path.read_text(), content)
            self.assertFalse(Path(f"{path}.cloudyy-legacy-backup").exists())

    def test_hypr_module_migration_rolls_back_all_files_after_late_write_failure(self):
        theme = self.prepare()
        hypr = self.config / "hypr"
        hypr.mkdir()
        colors = hypr / "colors.lua"
        look = hypr / "lookandfeel.lua"
        bindings = hypr / "bindings.lua"
        originals = {
            colors: LEGACY_HYPR_COLORS,
            look: "active_border = colors.primary,\ninactive_border = colors.inverse_on_surface,\n",
            bindings: (
                "-- ── Appearance ───────────────────────────────────────────────\n\n"
                'hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("cloudyy-theme toggle"), '
                '{ desc = "Toggle light/dark theme" })\n\n'
            ),
        }
        for path, content in originals.items():
            path.write_text(content, encoding="utf-8")
        program = (
            "source lib/cloudyy-theme/common.sh; "
            "source lib/cloudyy-theme/package.sh; "
            "source lib/cloudyy-theme/adapters.sh; "
            "replace_count=0; "
            "original_atomic=$(declare -f _atomic_replace_from | sed '1s/_atomic_replace_from/_original_atomic_replace_from/'); "
            "eval \"$original_atomic\"; "
            "_atomic_replace_from() { replace_count=$((replace_count + 1)); "
            "[[ $replace_count -eq 2 ]] && return 1; "
            "_original_atomic_replace_from \"$@\"; }; "
            "adapter_hypr_modules \"$1\""
        )

        result = subprocess.run(
            ["bash", "-c", program, "_", str(theme)], cwd=REPO_ROOT,
            env=self.environment, text=True, capture_output=True, check=False,
        )

        self.assertEqual(result.returncode, 1)
        for path, content in originals.items():
            self.assertEqual(path.read_text(), content)

    def test_reconcile_retires_only_owned_legacy_automode_units(self):
        self.prepare()
        units = self.home / ".config/systemd/user"
        units.mkdir(parents=True)
        service = units / "theme-automode.service"
        timer = units / "theme-automode.timer"
        service.write_text(
            "[Unit]\nDescription=Cloudyy — auto light/dark mode switcher\n"
            "After=graphical-session.target\n\n[Service]\nType=oneshot\n"
            f"ExecStart={self.home}/cloudyy-linux/bin/cloudyy-quickshell-automode-switch\n"
        )
        timer.write_text(
            "[Unit]\nDescription=Cloudyy — auto mode check timer\n\n"
            "[Timer]\nOnCalendar=*:0/5\nAccuracySec=30s\n\n"
            "[Install]\nWantedBy=timers.target\n"
        )
        self._write_fake(
            "systemctl",
            "printf 'systemctl %s\\n' \"$*\" >>\"$CLOUDYY_TEST_COMMAND_LOG\"\nexit 0",
        )

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(service.exists())
        self.assertFalse(timer.exists())
        commands = self.command_log.read_text()
        self.assertIn("systemctl --user disable --now theme-automode.timer", commands)
        self.assertIn("systemctl --user stop theme-automode.service", commands)
        self.assertIn("systemctl --user daemon-reload", commands)
        action = json.loads(
            (self.state / "cloudyy/current/activation.json").read_text()
        )["reconcile"]["actions"]["retire-automode"]
        self.assertEqual(action, {"status": "success"})

    def test_reconcile_preserves_unowned_automode_unit_without_systemctl_contact(self):
        self.prepare()
        units = self.home / ".config/systemd/user"
        units.mkdir(parents=True)
        service = units / "theme-automode.service"
        original = "[Service]\nExecStart=/home/user/personal-automation\n"
        service.write_text(original)
        self._write_fake(
            "systemctl",
            "printf 'systemctl %s\\n' \"$*\" >>\"$CLOUDYY_TEST_COMMAND_LOG\"\nexit 0",
        )

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        self.assertEqual(service.read_text(), original)
        commands = self.command_log.read_text() if self.command_log.exists() else ""
        self.assertNotIn("theme-automode", commands)
        actions = json.loads(
            (self.state / "cloudyy/current/activation.json").read_text()
        )["reconcile"]["actions"]
        self.assertEqual(actions["retire-automode"], {"status": "failure"})
        self.assertEqual(actions["reload-obsidian"], {"status": "skip"})

    def test_each_link_adapter_replaces_only_exact_legacy_link_and_keeps_narrow_backup(self):
        theme = self.prepare()
        self._create_consumer_roots()
        _, zen_profile, vault = self._create_profiles_and_vault()
        expected = self.expected_links(theme, zen_profile, vault)
        legacy_root = self.config / "matugen/generated"
        legacy_root.mkdir(parents=True)
        for path, legacy in self.legacy_links(zen_profile, vault).items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(legacy)

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        legacy = self.legacy_links(zen_profile, vault)
        for path, target in expected.items():
            with self.subTest(path=path):
                self.assertEqual(path.resolve(), target.resolve())
                if path in legacy:
                    backup = Path(f"{path}.cloudyy-legacy-backup")
                    self.assertTrue(backup.is_symlink())
                    self.assertIn("matugen/generated", os.readlink(backup))

    def test_each_link_adapter_preserves_an_occupied_modified_path_and_runs_later_adapters(self):
        theme = self.prepare()
        self._create_consumer_roots()
        _, zen_profile, vault = self._create_profiles_and_vault()
        expected = self.expected_links(theme, zen_profile, vault)
        for path in expected:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("hand-authored\n", encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        for path in expected:
            self.assertEqual(path.read_text(encoding="utf-8"), "hand-authored\n")
        activation = json.loads((self.state / "cloudyy/current/activation.json").read_text())
        self.assertEqual(activation["reconcile"]["status"], "failure")
        self.assertIn("mode-zen", activation["reconcile"]["actions"])

    def test_starship_migrates_deployed_zdotdir_assignment_to_direct_stable_boundary(self):
        self.prepare()
        zshrc = self.config / "zsh/.zshrc"
        zshrc.parent.mkdir(parents=True)
        legacy = 'export STARSHIP_CONFIG="$HOME/.config/matugen/generated/starship.toml"'
        zshrc.write_text(f"before\n{legacy}\nafter\n", encoding="utf-8")
        decoy = self.home / ".zshrc"
        decoy.write_text("home decoy\n", encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        desired = (
            'export STARSHIP_CONFIG="${XDG_STATE_HOME:-$HOME/.local/state}/cloudyy/'
            'current/theme/applications/starship.toml"'
        )
        self.assertEqual(zshrc.read_text(), f"before\n{desired}\nafter\n")
        self.assertEqual(Path(f"{zshrc}.cloudyy-legacy-backup").read_text(), f"before\n{legacy}\nafter\n")
        self.assertEqual(decoy.read_text(), "home decoy\n")
        self.assertFalse((self.config / "starship").exists())

    def test_inherited_path_selectors_cannot_escape_the_temporary_environment(self):
        self.prepare()
        legacy = 'export STARSHIP_CONFIG="$HOME/.config/matugen/generated/starship.toml"'
        zshrc = self.zdotdir / ".zshrc"
        zshrc.parent.mkdir(parents=True)
        zshrc.write_text(f"{legacy}\n", encoding="utf-8")
        escaped = Path(self.temporary_directory.name) / "outside-zdotdir"
        escaped.mkdir()
        sentinel = escaped / ".zshrc"
        sentinel.write_text(f"sentinel\n{legacy}\n", encoding="utf-8")

        previous = os.environ.get("ZDOTDIR")
        os.environ["ZDOTDIR"] = str(escaped)
        try:
            result = self.run_theme("reconcile")
        finally:
            if previous is None:
                os.environ.pop("ZDOTDIR", None)
            else:
                os.environ["ZDOTDIR"] = previous

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("cloudyy/current/theme/applications/starship.toml", zshrc.read_text())
        self.assertEqual(sentinel.read_text(), f"sentinel\n{legacy}\n")
        self.assertFalse(Path(f"{sentinel}.cloudyy-legacy-backup").exists())

    def test_starship_preserves_custom_assignment_as_conflict(self):
        self.prepare()
        zshrc = self.config / "zsh/.zshrc"
        zshrc.parent.mkdir(parents=True)
        custom = 'export STARSHIP_CONFIG="$HOME/my-starship.toml"\n'
        zshrc.write_text(custom, encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        self.assertEqual(zshrc.read_text(), custom)
        self.assertFalse(Path(f"{zshrc}.cloudyy-legacy-backup").exists())

    def test_starship_preserves_every_ambiguous_assignment_combination(self):
        self.prepare()
        desired = (
            'export STARSHIP_CONFIG="${XDG_STATE_HOME:-$HOME/.local/state}/cloudyy/'
            'current/theme/applications/starship.toml"'
        )
        legacy = 'export STARSHIP_CONFIG="$HOME/.config/matugen/generated/starship.toml"'
        custom = 'export STARSHIP_CONFIG="$HOME/personal-starship.toml"'
        cases = {
            "desired-and-custom": [desired, custom],
            "desired-and-legacy": [desired, legacy],
            "duplicate-desired": [desired, desired],
        }
        for name, assignments in cases.items():
            with self.subTest(name=name):
                case_root = Path(self.temporary_directory.name) / name
                case_zdotdir = case_root / "zsh"
                case_zdotdir.mkdir(parents=True)
                zshrc = case_zdotdir / ".zshrc"
                original = "before\n" + "\n".join(assignments) + "\nafter\n"
                zshrc.write_text(original, encoding="utf-8")
                environment = self.environment | {"ZDOTDIR": str(case_zdotdir)}

                result = subprocess.run(
                    [str(THEME_COMMAND), "reconcile"], cwd=REPO_ROOT, env=environment,
                    text=True, capture_output=True, check=False,
                )

                self.assertEqual(result.returncode, 20)
                self.assertEqual(zshrc.read_text(), original)
                self.assertFalse(Path(f"{zshrc}.cloudyy-legacy-backup").exists())

    def test_zen_replaces_exact_legacy_import_and_link_without_leaving_override(self):
        theme = self.prepare()
        _, profile, _ = self._create_profiles_and_vault()
        chrome = profile / "chrome"
        chrome.mkdir()
        legacy_link = chrome / "cloudyy-zen-colors.css"
        legacy_link.symlink_to(self.config / "matugen/generated/zen-userchrome.css")
        user_chrome = chrome / "userChrome.css"
        original = '@import "cloudyy-zen-colors.css";\n/* personal */\n'
        user_chrome.write_text(original, encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (chrome / "cloudyy-theme.css").resolve(), (theme / "applications/zen.css").resolve()
        )
        self.assertFalse(legacy_link.exists())
        self.assertTrue(Path(f"{legacy_link}.cloudyy-legacy-backup").is_symlink())
        self.assertEqual(user_chrome.read_text(), '@import "cloudyy-theme.css";\n/* personal */\n')
        self.assertEqual(Path(f"{user_chrome}.cloudyy-legacy-backup").read_text(), original)

    def test_zen_preserves_unowned_legacy_link_as_conflict(self):
        self.prepare()
        _, profile, _ = self._create_profiles_and_vault()
        chrome = profile / "chrome"
        chrome.mkdir()
        legacy_link = chrome / "cloudyy-zen-colors.css"
        legacy_link.symlink_to(self.home / "personal-zen.css")
        user_chrome = chrome / "userChrome.css"
        original = '@import "cloudyy-zen-colors.css";\n'
        user_chrome.write_text(original, encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        self.assertEqual(os.readlink(legacy_link), str(self.home / "personal-zen.css"))
        self.assertEqual(user_chrome.read_text(), original)
        self.assertFalse((chrome / "cloudyy-theme.css").exists())

    def test_zen_ambiguous_import_does_not_partially_move_legacy_link(self):
        self.prepare()
        _, profile, _ = self._create_profiles_and_vault()
        chrome = profile / "chrome"
        chrome.mkdir()
        legacy_link = chrome / "cloudyy-zen-colors.css"
        legacy_target = self.config / "matugen/generated/zen-userchrome.css"
        legacy_link.symlink_to(legacy_target)
        user_chrome = chrome / "userChrome.css"
        original = '@import "cloudyy-zen-colors.css";\n@import "cloudyy-zen-colors.css";\n'
        user_chrome.write_text(original, encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        self.assertEqual(os.readlink(legacy_link), str(legacy_target))
        self.assertFalse(Path(f"{legacy_link}.cloudyy-legacy-backup").exists())
        self.assertEqual(user_chrome.read_text(), original)

    def test_zen_occupied_import_backup_preserves_legacy_link_and_import_transaction(self):
        self.prepare()
        _, profile, _ = self._create_profiles_and_vault()
        chrome = profile / "chrome"
        chrome.mkdir()
        legacy_link = chrome / "cloudyy-zen-colors.css"
        legacy_target = self.config / "matugen/generated/zen-userchrome.css"
        legacy_link.symlink_to(legacy_target)
        user_chrome = chrome / "userChrome.css"
        original = '@import "cloudyy-zen-colors.css";\n/* personal */\n'
        user_chrome.write_text(original, encoding="utf-8")
        import_backup = Path(f"{user_chrome}.cloudyy-legacy-backup")
        import_backup.write_text("occupied\n", encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        self.assertEqual(os.readlink(legacy_link), str(legacy_target))
        self.assertEqual(user_chrome.read_text(), original)
        self.assertEqual(import_backup.read_text(), "occupied\n")
        self.assertFalse((chrome / "cloudyy-theme.css").exists())
        self.assertFalse(Path(f"{legacy_link}.cloudyy-legacy-backup").exists())

    def test_zen_occupied_link_backup_preserves_legacy_link_and_import_transaction(self):
        self.prepare()
        _, profile, _ = self._create_profiles_and_vault()
        chrome = profile / "chrome"
        chrome.mkdir()
        legacy_link = chrome / "cloudyy-zen-colors.css"
        legacy_target = self.config / "matugen/generated/zen-userchrome.css"
        legacy_link.symlink_to(legacy_target)
        link_backup = Path(f"{legacy_link}.cloudyy-legacy-backup")
        link_backup.symlink_to(self.home / "occupied.css")
        user_chrome = chrome / "userChrome.css"
        original = '@import "cloudyy-zen-colors.css";\n/* personal */\n'
        user_chrome.write_text(original, encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        self.assertEqual(os.readlink(legacy_link), str(legacy_target))
        self.assertEqual(os.readlink(link_backup), str(self.home / "occupied.css"))
        self.assertEqual(user_chrome.read_text(), original)
        self.assertFalse((chrome / "cloudyy-theme.css").exists())
        self.assertFalse(Path(f"{user_chrome}.cloudyy-legacy-backup").exists())

    def test_zen_import_write_failure_rolls_back_link_and_new_backups(self):
        theme = self.prepare()
        _, profile, _ = self._create_profiles_and_vault()
        chrome = profile / "chrome"
        chrome.mkdir()
        legacy_link = chrome / "cloudyy-zen-colors.css"
        legacy_target = self.config / "matugen/generated/zen-userchrome.css"
        legacy_link.symlink_to(legacy_target)
        user_chrome = chrome / "userChrome.css"
        original = '@import "cloudyy-zen-colors.css";\n/* personal */\n'
        user_chrome.write_text(original, encoding="utf-8")
        program = (
            "source lib/cloudyy-theme/common.sh; source lib/cloudyy-theme/package.sh; "
            "source lib/cloudyy-theme/adapters.sh; "
            "_atomic_replace_from() { "
            "[[ \"$1\" == */chrome/userChrome.css ]] && return 1; return 99; "
            "}; adapter_zen \"$1\""
        )

        result = subprocess.run(
            ["bash", "-c", program, "_", str(theme)], cwd=REPO_ROOT,
            env=self.environment, text=True, capture_output=True, check=False,
        )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(os.readlink(legacy_link), str(legacy_target))
        self.assertEqual(user_chrome.read_text(), original)
        self.assertFalse((chrome / "cloudyy-theme.css").exists())
        self.assertFalse(Path(f"{legacy_link}.cloudyy-legacy-backup").exists())
        self.assertFalse(Path(f"{user_chrome}.cloudyy-legacy-backup").exists())

    def test_obsidian_migrates_enabled_snippet_and_preserves_appearance_fields(self):
        theme = self.prepare()
        vault = self.home / "Notes/.obsidian"
        vault.mkdir(parents=True)
        appearance = vault / "appearance.json"
        original = {
            "accentColor": "#abcdef",
            "enabledCssSnippets": ["personal", "matugen-theme"],
            "cssTheme": "Things",
        }
        appearance.write_text(json.dumps(original) + "\n", encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        merged = json.loads(appearance.read_text())
        self.assertEqual(merged["enabledCssSnippets"], ["personal", "cloudyy-theme"])
        self.assertEqual(merged["accentColor"], "#abcdef")
        self.assertEqual(merged["cssTheme"], "Things")
        self.assertEqual(json.loads(Path(f"{appearance}.cloudyy-legacy-backup").read_text()), original)
        self.assertEqual(
            (vault / "snippets/cloudyy-theme.css").resolve(),
            (theme / "applications/obsidian.css").resolve(),
        )

    def test_obsidian_preserves_invalid_appearance_json_and_reports_failure(self):
        self.prepare()
        vault = self.home / "Notes/.obsidian"
        vault.mkdir(parents=True)
        appearance = vault / "appearance.json"
        appearance.write_text("{ invalid\n", encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        self.assertEqual(appearance.read_text(), "{ invalid\n")
        self.assertTrue(Path(f"{appearance}.cloudyy-invalid-backup").exists())
        self.assertFalse((vault / "snippets/cloudyy-theme.css").exists())

    def test_obsidian_link_conflict_does_not_partially_migrate_appearance(self):
        self.prepare()
        vault = self.home / "Notes/.obsidian"
        snippets = vault / "snippets"
        snippets.mkdir(parents=True)
        occupied = snippets / "cloudyy-theme.css"
        occupied.write_text("personal\n", encoding="utf-8")
        appearance = vault / "appearance.json"
        original = {"enabledCssSnippets": ["personal", "matugen-theme"], "keep": True}
        appearance.write_text(json.dumps(original) + "\n", encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        self.assertEqual(json.loads(appearance.read_text()), original)
        self.assertFalse(Path(f"{appearance}.cloudyy-legacy-backup").exists())
        self.assertEqual(occupied.read_text(), "personal\n")

    def test_btop_replaces_only_legacy_color_theme_with_backup(self):
        self.prepare()
        config = self.config / "btop/btop.conf"
        (self.config / "btop/themes").mkdir(parents=True)
        original = 'proc_sorting = "cpu lazy"\ncolor_theme = "matugen"\n'
        config.write_text(original, encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(config.read_text(), 'proc_sorting = "cpu lazy"\ncolor_theme = "cloudyy"\n')
        self.assertEqual(Path(f"{config}.cloudyy-legacy-backup").read_text(), original)

    def test_btop_preserves_custom_color_theme_as_conflict(self):
        self.prepare()
        config = self.config / "btop/btop.conf"
        (self.config / "btop/themes").mkdir(parents=True)
        custom = 'color_theme = "tokyo-night"\n'
        config.write_text(custom, encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        self.assertEqual(config.read_text(), custom)
        self.assertFalse(Path(f"{config}.cloudyy-legacy-backup").exists())

    def test_chromium_marker_preserves_comments_flags_and_never_touches_other_browsers(self):
        theme = self.prepare()
        flags = self.config / "chromium-flags.conf"
        flags.write_text("# user note\n--enable-features=UseOzonePlatform\n", encoding="utf-8")
        chrome = self.config / "chrome-flags.conf"
        brave = self.config / "brave-flags.conf"
        chrome.write_text("chrome\n", encoding="utf-8")
        brave.write_text("brave\n", encoding="utf-8")

        first = self.run_adapter("adapter_chromium", str(theme))
        first_contents = flags.read_text(encoding="utf-8")
        second = self.run_adapter("adapter_chromium", str(theme))

        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(flags.read_text(encoding="utf-8"), first_contents)
        self.assertIn("# user note", first_contents)
        self.assertIn("--enable-features=UseOzonePlatform", first_contents)
        self.assertIn("# >>> cloudyy-theme chromium >>>", first_contents)
        self.assertIn(str(self.state / "cloudyy/current/theme/applications/chromium"), first_contents)
        self.assertEqual(chrome.read_text(), "chrome\n")
        self.assertEqual(brave.read_text(), "brave\n")

    def test_chromium_rejects_ambiguous_markers_and_unowned_load_extension_without_rewrite(self):
        theme = self.prepare()
        flags = self.config / "chromium-flags.conf"
        cases = (
            "# >>> cloudyy-theme chromium >>>\n# >>> cloudyy-theme chromium >>>\n",
            "--load-extension=/home/user/extension\n# keep\n",
        )
        for contents in cases:
            with self.subTest(contents=contents):
                flags.write_text(contents, encoding="utf-8")
                result = self.run_adapter("adapter_chromium", str(theme))
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(flags.read_text(encoding="utf-8"), contents)

    def test_running_chromium_is_reported_pending_and_never_signalled(self):
        theme = self.prepare()
        self._write_fake("pgrep", "[[ \"$*\" == *chromium* || \"$*\" == *awww-daemon* ]]")
        self._write_fake("pkill", "printf 'pkill %s\\n' \"$*\" >>\"$CLOUDYY_TEST_COMMAND_LOG\"; exit 99")

        result = self.run_adapter("adapter_chromium", str(theme))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pending restart", result.stderr.lower())
        self.assertFalse(self.command_log.exists())

    def test_vscode_helper_merges_only_curated_workbench_keys_and_preserves_other_settings(self):
        theme = self.prepare()
        source = theme / "applications/vscode.json"
        settings = self.config / "VSCodium/User/settings.json"
        settings.parent.mkdir(parents=True)
        settings.write_text(json.dumps({
            "editor.fontSize": 15,
            "workbench.colorCustomizations": {"user.key": "#010203", "focusBorder": "#FFFFFF"},
            "editor.tokenColorCustomizations": {"comments": "#123456"},
        }) + "\n", encoding="utf-8")

        result = subprocess.run(
            [str(CODE_UPDATER), str(source)], cwd=REPO_ROOT, env=self.environment,
            text=True, capture_output=True, check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        merged = json.loads(settings.read_text())
        curated = json.loads(source.read_text())["workbench.colorCustomizations"]
        self.assertEqual(merged["editor.fontSize"], 15)
        self.assertEqual(merged["editor.tokenColorCustomizations"], {"comments": "#123456"})
        self.assertEqual(merged["workbench.colorCustomizations"]["user.key"], "#010203")
        self.assertEqual(merged["workbench.colorCustomizations"]["focusBorder"], curated["focusBorder"])

    def test_vscode_helper_preserves_invalid_json_and_reports_failure(self):
        theme = self.prepare()
        settings = self.config / "Code/User/settings.json"
        settings.parent.mkdir(parents=True)
        settings.write_text("{ invalid\n", encoding="utf-8")

        result = subprocess.run(
            [str(CODE_UPDATER), str(theme / "applications/vscode.json")], cwd=REPO_ROOT,
            env=self.environment, text=True, capture_output=True, check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(settings.read_text(), "{ invalid\n")
        self.assertTrue(Path(f"{settings}.cloudyy-invalid-backup").exists())

    def test_vscode_helper_rejects_symlinked_settings_without_replacing_it_or_target(self):
        theme = self.prepare()
        settings = self.config / "Code/User/settings.json"
        settings.parent.mkdir(parents=True)
        external = self.home / "external-settings.json"
        original = '{"editor.fontSize": 17}\n'
        external.write_text(original, encoding="utf-8")
        settings.symlink_to(external)

        result = subprocess.run(
            [str(CODE_UPDATER), str(theme / "applications/vscode.json")], cwd=REPO_ROOT,
            env=self.environment, text=True, capture_output=True, check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(settings.is_symlink())
        self.assertEqual(os.readlink(settings), str(external))
        self.assertEqual(external.read_text(), original)

    def test_declared_mode_updates_only_owned_preferences(self):
        theme = self.prepare()
        self._create_consumer_roots()
        firefox_profile, zen_profile, _ = self._create_profiles_and_vault()
        qt = self.config / "qt6ct/qt6ct.conf"
        qt.write_text("[Appearance]\nstyle=Fusion\ncolor_scheme_path=old\n[Fonts]\nfixed=Keep\n", encoding="utf-8")
        for profile in (firefox_profile, zen_profile):
            (profile / "user.js").write_text(
                '// keep\nuser_pref("unrelated.pref", 42);\n'
                'user_pref("ui.systemUsesDarkTheme", 0);\n', encoding="utf-8"
            )

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("color_scheme_path=/usr/share/qt6ct/colors/darker.conf", qt.read_text())
        self.assertIn("fixed=Keep", qt.read_text())
        for profile in (firefox_profile, zen_profile):
            contents = (profile / "user.js").read_text()
            self.assertIn('// keep\nuser_pref("unrelated.pref", 42);', contents)
            self.assertEqual(contents.count('user_pref("ui.systemUsesDarkTheme"'), 1)
            self.assertIn('user_pref("ui.systemUsesDarkTheme", 1);', contents)
        self.assertIn('user_pref("zen.view.window.scheme", 0);', (zen_profile / "user.js").read_text())
        commands = self.command_log.read_text()
        self.assertIn("color-scheme prefer-dark", commands)
        self.assertIn("gtk-application-prefer-dark-mode true", commands)

    def test_gsettings_optional_legacy_key_and_portal_skip_are_accurate(self):
        self.prepare()
        self._write_fake(
            "gsettings",
            "printf 'gsettings %s\\n' \"$*\" >>\"$CLOUDYY_TEST_COMMAND_LOG\"\n"
            "if [[ \"${1:-}\" == list-schemas ]]; then printf 'org.gnome.desktop.interface\\n'; fi\n"
            "if [[ \"${1:-}\" == list-keys ]]; then printf 'color-scheme\\n'; fi\n"
            "exit 0",
        )

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.command_log.read_text()
        self.assertIn("set org.gnome.desktop.interface color-scheme prefer-dark", commands)
        self.assertNotIn("set org.gnome.desktop.interface gtk-application-prefer-dark-mode", commands)
        actions = json.loads(
            (self.state / "cloudyy/current/activation.json").read_text()
        )["reconcile"]["actions"]
        self.assertEqual(actions["mode-gsettings"], {"status": "success"})
        self.assertEqual(actions["mode-portal"], {"status": "skip"})

    def test_qt5_and_qt6_use_their_matching_palette_paths(self):
        self.prepare()
        qt5 = self.config / "qt5ct/qt5ct.conf"
        qt6 = self.config / "qt6ct/qt6ct.conf"
        qt5.parent.mkdir(parents=True)
        qt6.parent.mkdir(parents=True)
        qt5.write_text("[Appearance]\n", encoding="utf-8")
        qt6.write_text("[Appearance]\n", encoding="utf-8")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("/usr/share/qt5ct/colors/darker.conf", qt5.read_text())
        self.assertIn("/usr/share/qt6ct/colors/darker.conf", qt6.read_text())

    def test_existing_but_inapplicable_profile_and_qt_paths_record_clean_skips(self):
        self.prepare()
        firefox_ini = self.home / ".mozilla/firefox/profiles.ini"
        firefox_ini.parent.mkdir(parents=True)
        firefox_ini.write_text("[Profile0]\nIsRelative=1\nPath=missing\n", encoding="utf-8")
        zen_ini = self.config / "zen/profiles.ini"
        zen_ini.parent.mkdir(parents=True)
        zen_ini.write_text("[Profile0]\nIsRelative=1\nPath=missing\n", encoding="utf-8")
        qt = self.config / "qt6ct/qt6ct.conf"
        qt.mkdir(parents=True)

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        actions = json.loads(
            (self.state / "cloudyy/current/activation.json").read_text()
        )["reconcile"]["actions"]
        self.assertEqual(actions["mode-qt"], {"status": "skip"})
        self.assertEqual(actions["mode-firefox"], {"status": "skip"})
        self.assertEqual(actions["mode-zen"], {"status": "skip"})

    def test_running_thunar_is_quit_and_restarted_without_inheriting_theme_lock(self):
        self.prepare()
        marker = Path(self.temporary_directory.name) / "thunar-running"
        marker.touch()
        self.environment["CLOUDYY_TEST_THUNAR_MARKER"] = str(marker)
        self._write_fake(
            "pgrep",
            'if [[ "$*" == *awww-daemon* ]]; then exit 0; fi\n'
            'if [[ "$*" == *Thunar* || "$*" == *thunar* ]]; then '
            '[[ -e "$CLOUDYY_TEST_THUNAR_MARKER" ]]; exit; fi\nexit 1',
        )
        self._write_fake(
            "thunar",
            'printf "thunar %s\\n" "$*" >>"$CLOUDYY_TEST_COMMAND_LOG"\n'
            'if [[ "${1:-}" == -q ]]; then rm -f "$CLOUDYY_TEST_THUNAR_MARKER"; exit 0; fi\n'
            'if [[ "${1:-}" == --daemon ]]; then touch "$CLOUDYY_TEST_THUNAR_MARKER"; sleep 4; exit 0; fi\n'
            'exit 2',
        )

        result = self.run_theme("reconcile")
        started = time.monotonic()
        current = self.run_theme("current")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(current.returncode, 0, current.stderr)
        self.assertLess(time.monotonic() - started, 2)
        commands = self.command_log.read_text()
        self.assertIn("thunar -q", commands)
        self.assertIn("thunar --daemon", commands)
        actions = json.loads(
            (self.state / "cloudyy/current/activation.json").read_text()
        )["reconcile"]["actions"]
        self.assertEqual(actions["reload-gtk"], {"status": "success"})

    def test_thunar_waits_for_old_process_exit_before_starting_new_daemon(self):
        self.prepare()
        marker = Path(self.temporary_directory.name) / "thunar-running"
        marker.touch()
        self.environment["CLOUDYY_TEST_THUNAR_MARKER"] = str(marker)
        self._write_fake(
            "pgrep",
            'if [[ "$*" == *awww-daemon* ]]; then exit 0; fi\n'
            'if [[ "$*" == *Thunar* || "$*" == *thunar* ]]; then '
            '[[ -e "$CLOUDYY_TEST_THUNAR_MARKER" ]]; exit; fi\nexit 1',
        )
        self._write_fake(
            "thunar",
            'printf "thunar %s\\n" "$*" >>"$CLOUDYY_TEST_COMMAND_LOG"\n'
            'if [[ "${1:-}" == -q ]]; then '
            '(sleep 0.3; rm -f "$CLOUDYY_TEST_THUNAR_MARKER") >/dev/null 2>&1 & exit 0; fi\n'
            'if [[ "${1:-}" == --daemon ]]; then '
            'if [[ -e "$CLOUDYY_TEST_THUNAR_MARKER" ]]; then '
            'printf "premature-daemon\\n" >>"$CLOUDYY_TEST_COMMAND_LOG"; exit 5; fi; '
            'touch "$CLOUDYY_TEST_THUNAR_MARKER"; sleep 2; fi',
        )

        started = time.monotonic()
        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertGreaterEqual(time.monotonic() - started, 0.25)
        commands = self.command_log.read_text()
        self.assertIn("thunar --daemon", commands)
        self.assertNotIn("premature-daemon", commands)

    def test_thunar_refresh_failure_is_recorded_and_later_passive_actions_still_run(self):
        self.prepare()
        marker = Path(self.temporary_directory.name) / "thunar-running"
        marker.touch()
        self.environment["CLOUDYY_TEST_THUNAR_MARKER"] = str(marker)
        self._write_fake(
            "pgrep",
            'if [[ "$*" == *awww-daemon* ]]; then exit 0; fi\n'
            'if [[ "$*" == *Thunar* || "$*" == *thunar* ]]; then exit 0; fi\nexit 1',
        )
        self._write_fake(
            "thunar",
            'printf "thunar %s\\n" "$*" >>"$CLOUDYY_TEST_COMMAND_LOG"\n'
            '[[ "${1:-}" == -q ]] && exit 9\nexit 0',
        )

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        actions = json.loads(
            (self.state / "cloudyy/current/activation.json").read_text()
        )["reconcile"]["actions"]
        self.assertEqual(actions["reload-gtk"], {"status": "failure"})
        self.assertEqual(actions["reload-obsidian"], {"status": "skip"})
        self.assertIn("1 failed", result.stdout)

    def test_thunar_old_process_exit_timeout_records_failure_without_relaunch(self):
        self.prepare()
        self._write_fake(
            "pgrep",
            'if [[ "$*" == *awww-daemon* ]]; then exit 0; fi\n'
            'if [[ "$*" == *Thunar* || "$*" == *thunar* ]]; then exit 0; fi\nexit 1',
        )
        self._write_fake(
            "thunar",
            'printf "thunar %s\\n" "$*" >>"$CLOUDYY_TEST_COMMAND_LOG"\n'
            '[[ "${1:-}" == -q ]] && exit 0\nexit 7',
        )

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        commands = self.command_log.read_text()
        self.assertIn("thunar -q", commands)
        self.assertNotIn("thunar --daemon", commands)
        actions = json.loads(
            (self.state / "cloudyy/current/activation.json").read_text()
        )["reconcile"]["actions"]
        self.assertEqual(actions["reload-gtk"], {"status": "failure"})
        self.assertEqual(actions["reload-obsidian"], {"status": "skip"})

    def test_thunar_new_daemon_failure_records_failure_and_continues(self):
        self.prepare()
        marker = Path(self.temporary_directory.name) / "thunar-running"
        marker.touch()
        self.environment["CLOUDYY_TEST_THUNAR_MARKER"] = str(marker)
        self._write_fake(
            "pgrep",
            'if [[ "$*" == *awww-daemon* ]]; then exit 0; fi\n'
            'if [[ "$*" == *Thunar* || "$*" == *thunar* ]]; then '
            '[[ -e "$CLOUDYY_TEST_THUNAR_MARKER" ]]; exit; fi\nexit 1',
        )
        self._write_fake(
            "thunar",
            'printf "thunar %s\\n" "$*" >>"$CLOUDYY_TEST_COMMAND_LOG"\n'
            'if [[ "${1:-}" == -q ]]; then rm -f "$CLOUDYY_TEST_THUNAR_MARKER"; exit 0; fi\n'
            '[[ "${1:-}" == --daemon ]] && exit 9\nexit 7',
        )

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        self.assertIn("thunar --daemon", self.command_log.read_text())
        actions = json.loads(
            (self.state / "cloudyy/current/activation.json").read_text()
        )["reconcile"]["actions"]
        self.assertEqual(actions["reload-gtk"], {"status": "failure"})
        self.assertEqual(actions["reload-obsidian"], {"status": "skip"})

    def test_reconcile_records_exact_actions_and_attempts_reload_after_adapter_failure(self):
        self.prepare()
        self._create_consumer_roots()
        conflict = self.config / "kitty/current-theme.conf"
        conflict.write_text("mine\n", encoding="utf-8")
        self._write_fake("hyprctl", "printf 'hyprctl %s\\n' \"$*\" >>\"$CLOUDYY_TEST_COMMAND_LOG\"")
        self._write_fake("pgrep", "[[ \"$*\" == *Hyprland* || \"$*\" == *awww-daemon* ]]")

        result = self.run_theme("reconcile")

        self.assertEqual(result.returncode, 20)
        self.assertIn("hyprctl reload", self.command_log.read_text())
        activation = json.loads((self.state / "cloudyy/current/activation.json").read_text())
        actions = activation["reconcile"]["actions"]
        self.assertEqual(set(actions), {
            "wallpaper", "compatibility-state", "link-boundary", "link-kitty", "link-gtk3",
            "link-gtk4", "link-wlogout", "link-btop", "link-starship",
            "link-hyprland", "migrate-hypr-modules", "link-zen", "link-obsidian", "chromium", "vscode",
            "retire-automode",
            "mode-gsettings", "mode-portal", "mode-qt", "mode-firefox", "mode-zen",
            "reload-hyprland", "reload-quickshell", "reload-kitty", "reload-nvim",
            "reload-btop", "reload-gtk", "reload-wlogout", "reload-starship",
            "reload-zen", "reload-obsidian", "reload-chromium",
        })
        self.assertEqual(actions["link-kitty"], {"status": "failure"})
        self.assertIn(actions["reload-hyprland"]["status"], ("success", "skip"))
        for action in (
            "reload-wlogout", "reload-starship", "reload-zen",
            "reload-obsidian", "reload-chromium",
        ):
            self.assertEqual(actions[action], {"status": "skip"})
        self.assertRegex(result.stdout, r"cloudyy-theme: reconcile: \d+ success, \d+ skipped, \d+ failed")
        self.assertIn("failed actions: link-kitty", result.stdout)
        self.assertTrue(self.command_log.is_relative_to(Path(self.temporary_directory.name)))


if __name__ == "__main__":
    unittest.main()
