"""End-to-end activation contract for a shipped curated theme."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
THEME_COMMAND = ROOT / "bin/cloudyy-theme"
RECONCILE_ACTIONS = {
    "wallpaper", "compatibility-state", "link-boundary", "link-kitty", "link-gtk3",
    "link-gtk4", "link-wlogout", "link-btop", "link-starship",
    "link-hyprland", "migrate-hypr-modules", "link-zen", "link-obsidian", "chromium", "vscode",
    "retire-automode", "mode-gsettings", "mode-portal", "mode-qt", "mode-firefox",
    "mode-zen", "reload-hyprland", "reload-quickshell", "reload-kitty",
    "reload-nvim", "reload-btop", "reload-gtk", "reload-wlogout", "reload-starship",
    "reload-zen", "reload-obsidian", "reload-chromium",
}


class CuratedThemeEndToEndTests(unittest.TestCase):
    def test_use_nord_activates_finished_assets_without_a_generator(self):
        with tempfile.TemporaryDirectory(prefix="cloudyy-theme-e2e-") as temp:
            root = Path(temp)
            home = root / "home"
            state = root / "state"
            config = root / "config"
            runtime = root / "runtime"
            fake_bin = root / "bin"
            command_log = root / "commands.log"
            for directory in (home, state, config, runtime, fake_bin, home / "Wallpapers"):
                directory.mkdir()

            for command in (
                "awk", "bash", "cat", "chmod", "cmp", "cp", "cut", "dirname",
                "find", "flock", "grep", "identify", "jq", "ln", "mkdir",
                "mktemp", "mv", "python3", "readlink", "realpath", "rm", "rmdir",
                "sed", "sleep", "sort", "stat", "tail", "touch",
            ):
                (fake_bin / command).symlink_to(shutil.which(command))

            def fake(name: str, body: str) -> None:
                path = fake_bin / name
                path.write_text(f"#!/usr/bin/env bash\n{body}\n")
                path.chmod(0o755)

            fake("pgrep", '[[ "$*" == *awww-daemon* ]]')
            fake("awww", 'printf "awww %s\\n" "$*" >>"$CLOUDYY_E2E_LOG"')
            fake("awww-daemon", "exit 0")
            fake(
                "gsettings",
                'printf "gsettings %s\\n" "$*" >>"$CLOUDYY_E2E_LOG"\n'
                '[[ "${1:-}" == list-schemas ]] && printf "org.gnome.desktop.interface\\n"\n'
                '[[ "${1:-}" == list-keys ]] && printf "color-scheme\\ngtk-application-prefer-dark-mode\\n"\n'
                "exit 0",
            )
            for command in ("chromium", "hyprctl", "quickshell", "kitty", "nvim", "pkill", "thunar"):
                fake(command, f'printf "{command} %s\\n" "$*" >>"$CLOUDYY_E2E_LOG"')

            for relative in (
                "kitty", "wlogout", "btop/themes", "zsh",
                "hypr", "chromium", "Code/User", "qt6ct", "cloudyy",
            ):
                (config / relative).mkdir(parents=True)
            (config / "zsh/.zshrc").write_text(
                'export STARSHIP_CONFIG="$HOME/.config/matugen/generated/starship.toml"\n'
                "export PERSONAL_SHELL_VALUE=kept\n"
            )
            (config / "btop/btop.conf").write_text(
                'color_theme = "matugen"\nupdate_ms = 2000\n'
            )
            (config / "chromium-flags.conf").write_text("--ozone-platform=wayland\n")
            (config / "Code/User/settings.json").write_text(
                '{"editor.fontSize":14,"workbench.colorCustomizations":{"personal":"#fff"}}\n'
            )
            firefox = home / ".mozilla/firefox/profile.default"
            firefox.mkdir(parents=True)
            (home / ".mozilla/firefox/profiles.ini").write_text(
                "[Profile0]\nName=default\nIsRelative=1\nPath=profile.default\n"
            )
            zen = config / "zen/profile.default"
            zen.mkdir(parents=True)
            (config / "zen/profiles.ini").write_text(
                "[Profile0]\nIsRelative=1\nPath=profile.default\n"
            )
            (zen / "zen-themes.json").write_text("{}\n")
            vault = home / "Notes/.obsidian"
            vault.mkdir(parents=True)

            environment = os.environ | {
                "HOME": str(home),
                "XDG_STATE_HOME": str(state),
                "XDG_CONFIG_HOME": str(config),
                "XDG_RUNTIME_DIR": str(runtime),
                "ZDOTDIR": str(config / "zsh"),
                "CLOUDYY_WALLPAPER_DIR": str(home / "Wallpapers"),
                "CLOUDYY_E2E_LOG": str(command_log),
                "PATH": str(fake_bin),
            }

            first = subprocess.run(
                [str(THEME_COMMAND), "use", "nord"], cwd=ROOT, env=environment,
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(first.returncode, 0, first.stderr)

            active = state / "cloudyy/current/theme"
            metadata = json.loads((active / "theme.json").read_text())
            self.assertEqual((metadata["slug"], metadata["mode"]), ("nord", "dark"))
            wallpaper = active / "wallpapers/1.jpg"
            saved = (config / "hypr/theme_state/state.conf").read_text()
            self.assertIn('THEME_MODE="dark"', saved)
            self.assertIn(f'CURRENT_WALL="{wallpaper.resolve()}"', saved)
            snapshot = config / "hypr/theme_state/current_wallpaper/current.jpg"
            digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
            self.assertEqual(digest(snapshot), digest(wallpaper))

            activation = json.loads((state / "cloudyy/current/activation.json").read_text())
            self.assertEqual(activation["reconcile"]["status"], "success")
            self.assertEqual(set(activation["reconcile"]["actions"]), RECONCILE_ACTIONS)
            self.assertNotIn(
                "failure", {item["status"] for item in activation["reconcile"]["actions"].values()}
            )
            self.assertEqual(
                (config / "hypr/cloudyy-theme.conf").resolve(),
                (active / "applications/hyprland.conf").resolve(),
            )
            self.assertEqual(
                (config / "kitty/current-theme.conf").resolve(),
                (active / "applications/kitty.conf").resolve(),
            )
            expected_links = {
                config / "cloudyy/current-theme": active,
                config / "gtk-3.0/cloudyy-theme.css": active / "applications/gtk-3.css",
                config / "gtk-4.0/cloudyy-theme.css": active / "applications/gtk-4.css",
                config / "wlogout/cloudyy-theme.css": active / "applications/wlogout.css",
                config / "btop/themes/cloudyy.theme": active / "applications/btop.theme",
                vault / "snippets/cloudyy-theme.css": active / "applications/obsidian.css",
            }
            for link, target in expected_links.items():
                with self.subTest(link=link):
                    self.assertTrue(link.is_symlink())
                    self.assertEqual(link.resolve(), target.resolve())
            zen_css = zen / "chrome/zen-themes/cloudyy-theme/chrome.css"
            self.assertTrue(zen_css.is_file())
            self.assertFalse(zen_css.is_symlink())
            zen_css_lines = zen_css.read_text().splitlines(keepends=True)
            self.assertEqual(
                zen_css_lines[0],
                f"/* cloudyy-generation: {active.resolve().parent.name} */\n",
            )
            self.assertEqual(
                "".join(zen_css_lines[1:]),
                (active / "applications/zen.css").read_text(),
            )
            manifest = json.loads((zen / "zen-themes.json").read_text())
            self.assertEqual(manifest["cloudyy-theme"]["cloudyyOwner"], "zen-live-theme-v1")
            self.assertFalse((zen / "chrome/userChrome.css").exists())
            self.assertFalse((zen / "chrome/cloudyy-theme.css").exists())
            vscode = json.loads((config / "Code/User/settings.json").read_text())
            self.assertEqual(vscode["editor.fontSize"], 14)
            self.assertEqual(vscode["workbench.colorCustomizations"]["personal"], "#fff")
            curated_vscode = json.loads((active / "applications/vscode.json").read_text())[
                "workbench.colorCustomizations"
            ]
            for key, value in curated_vscode.items():
                self.assertEqual(vscode["workbench.colorCustomizations"][key], value)

            chromium_flags = (config / "chromium-flags.conf").read_text()
            self.assertIn("--ozone-platform=wayland", chromium_flags)
            self.assertEqual(chromium_flags.count("# >>> cloudyy-theme chromium >>>"), 1)
            self.assertIn(
                f"--load-extension={state}/cloudyy/current/theme/applications/chromium",
                chromium_flags,
            )
            self.assertEqual(
                (config / "zsh/.zshrc.cloudyy-legacy-backup").read_text(),
                'export STARSHIP_CONFIG="$HOME/.config/matugen/generated/starship.toml"\n'
                "export PERSONAL_SHELL_VALUE=kept\n",
            )
            self.assertIn("PERSONAL_SHELL_VALUE=kept", (config / "zsh/.zshrc").read_text())
            self.assertEqual(
                (config / "btop/btop.conf.cloudyy-legacy-backup").read_text(),
                'color_theme = "matugen"\nupdate_ms = 2000\n',
            )
            self.assertIn("update_ms = 2000", (config / "btop/btop.conf").read_text())

            commands = command_log.read_text().lower()
            self.assertIn("awww img", commands)
            self.assertIn("color-scheme prefer-dark", commands)
            self.assertNotIn("matugen", commands)
            self.assertNotIn("pywalfox", commands)

            before_links = {
                path: os.readlink(path)
                for path in (config / "hypr/cloudyy-theme.conf", config / "kitty/current-theme.conf")
            }
            second = subprocess.run(
                [str(THEME_COMMAND), "reconcile"], cwd=ROOT, env=environment,
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(
                before_links,
                {path: os.readlink(path) for path in before_links},
            )

            # An existing but invalid shipped package fails native/schema validation.
            sandbox_repo = root / "invalid-package-repository"
            (sandbox_repo / "bin").mkdir(parents=True)
            shutil.copy2(THEME_COMMAND, sandbox_repo / "bin/cloudyy-theme")
            shutil.copytree(ROOT / "lib/cloudyy-theme", sandbox_repo / "lib/cloudyy-theme")
            shutil.copytree(ROOT / "themes", sandbox_repo / "themes")
            sandbox_command = sandbox_repo / "bin/cloudyy-theme"
            sandbox_state = root / "invalid-state"
            sandbox_config = root / "invalid-config"
            sandbox_state.mkdir()
            sandbox_config.mkdir()
            sandbox_environment = environment | {
                "XDG_STATE_HOME": str(sandbox_state),
                "XDG_CONFIG_HOME": str(sandbox_config),
            }
            sandbox_metadata = sandbox_repo / "themes/nord/theme.json"
            valid_metadata = sandbox_metadata.read_bytes()
            invalid_metadata = json.loads(valid_metadata)
            invalid_metadata["mode"] = "sepia"
            sandbox_metadata.write_text(json.dumps(invalid_metadata) + "\n")
            invalid = subprocess.run(
                [str(sandbox_command), "prepare", "nord"], cwd=sandbox_repo,
                env=sandbox_environment, text=True, capture_output=True, check=False,
            )
            self.assertEqual(invalid.returncode, 10)
            self.assertFalse((sandbox_state / "cloudyy/current").exists())

            # A subsequent operation prunes an interrupted private temp stage and
            # atomically promotes only a completely validated package.
            sandbox_metadata.write_bytes(valid_metadata)
            interrupted = sandbox_state / "cloudyy/theme-stages/.tmp.interrupted"
            interrupted.mkdir(parents=True)
            (interrupted / "partial").write_text("incomplete\n")
            resumed = subprocess.run(
                [str(sandbox_command), "prepare", "nord"], cwd=sandbox_repo,
                env=sandbox_environment, text=True, capture_output=True, check=False,
            )
            self.assertEqual(resumed.returncode, 0, resumed.stderr)
            self.assertFalse(interrupted.exists())
            self.assertEqual(
                (sandbox_state / "cloudyy/current/theme.name").read_text(), "nord\n"
            )

            # An occupied user boundary fails closed and preserves the user's bytes.
            occupied = config / "wlogout/cloudyy-theme.css"
            occupied.unlink()
            occupied.write_text("personal boundary\n")
            conflict = subprocess.run(
                [str(THEME_COMMAND), "reconcile"], cwd=ROOT, env=environment,
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(conflict.returncode, 20)
            self.assertEqual(occupied.read_text(), "personal boundary\n")
            conflict_activation = json.loads(
                (state / "cloudyy/current/activation.json").read_text()
            )
            self.assertEqual(
                conflict_activation["reconcile"]["actions"]["link-wlogout"],
                {"status": "failure"},
            )
            occupied.unlink()
            repaired = subprocess.run(
                [str(THEME_COMMAND), "reconcile"], cwd=ROOT, env=environment,
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(repaired.returncode, 0, repaired.stderr)

            # Wallpaper and reload failures are recorded without falsifying saved state.
            saved_before_failure = (config / "hypr/theme_state/state.conf").read_bytes()
            fake("awww", "exit 9")
            wallpaper_failure = subprocess.run(
                [str(THEME_COMMAND), "use", "nord"], cwd=ROOT, env=environment,
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(wallpaper_failure.returncode, 20)
            self.assertEqual(
                (config / "hypr/theme_state/state.conf").read_bytes(), saved_before_failure
            )
            failed_activation = json.loads(
                (state / "cloudyy/current/activation.json").read_text()
            )
            self.assertEqual(
                failed_activation["reconcile"]["actions"]["wallpaper"],
                {"status": "failure"},
            )
            fake("awww", 'printf "awww %s\\n" "$*" >>"$CLOUDYY_E2E_LOG"')

            fake("pgrep", '[[ "$*" == *awww-daemon* || "$*" == *Hyprland* ]]')
            fake("hyprctl", "exit 9")
            reload_failure = subprocess.run(
                [str(THEME_COMMAND), "reconcile"], cwd=ROOT, env=environment,
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(reload_failure.returncode, 20)
            failed_activation = json.loads(
                (state / "cloudyy/current/activation.json").read_text()
            )
            self.assertEqual(
                failed_activation["reconcile"]["actions"]["reload-hyprland"],
                {"status": "failure"},
            )
            fake("pgrep", '[[ "$*" == *awww-daemon* ]]')
            fake("hyprctl", 'printf "hyprctl %s\\n" "$*" >>"$CLOUDYY_E2E_LOG"')

            # A promoted stage can be rolled back through the retained previous pointer.
            recover_target = os.readlink(state / "cloudyy/current")
            promoted = subprocess.run(
                [str(THEME_COMMAND), "prepare", "nord"], cwd=ROOT, env=environment,
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(promoted.returncode, 0, promoted.stderr)
            self.assertNotEqual(os.readlink(state / "cloudyy/current"), recover_target)
            recovered = subprocess.run(
                [str(THEME_COMMAND), "recover-previous"], cwd=ROOT, env=environment,
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(recovered.returncode, 0, recovered.stderr)
            self.assertEqual(os.readlink(state / "cloudyy/current"), recover_target)


if __name__ == "__main__":
    unittest.main()
