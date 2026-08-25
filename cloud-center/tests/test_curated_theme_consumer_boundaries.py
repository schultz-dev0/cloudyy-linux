"""Permanent native consumer boundaries for curated Cloudyy themes."""

from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class CuratedThemeConsumerBoundaryTests(unittest.TestCase):
    def test_hyprland_reads_only_the_stable_semantic_color_boundary(self):
        colors = (ROOT / "install/assets/defaults/hypr/colors.lua").read_text()
        look = (ROOT / "install/assets/defaults/hypr/lookandfeel.lua").read_text()

        self.assertNotIn("matugen", colors.lower())
        self.assertIn("/hypr/cloudyy-theme.conf", colors)
        self.assertIn("colors.accent", look)
        self.assertIn("colors.border", look)
        self.assertNotIn("colors.primary", look)
        self.assertNotIn("colors.inverse_on_surface", look)

    @unittest.skipUnless(shutil.which("lua"), "Lua is unavailable")
    def test_hyprland_loader_parses_curated_values_and_ignores_unknown_keys(self):
        with tempfile.TemporaryDirectory(prefix="cloudyy-hypr-boundary-") as temp:
            root = Path(temp)
            config = root / "config/hypr"
            config.mkdir(parents=True)
            (config / "cloudyy-theme.conf").write_text(
                "$accent = rgb(010203)\n$border = rgb(a0b0c0)\n"
                "$unowned_property = rgb(ffffff)\n"
            )
            program = (
                "local c = dofile(os.getenv('CLOUDYY_TEST_COLORS_LUA')); "
                "assert(c.accent == 'rgb(010203)'); "
                "assert(c.border == 'rgb(a0b0c0)'); "
                "assert(c.unowned_property == nil)"
            )
            result = subprocess.run(
                ["lua", "-e", program],
                env=os.environ | {
                    "HOME": str(root / "home"),
                    "XDG_CONFIG_HOME": str(root / "config"),
                    "CLOUDYY_TEST_COLORS_LUA": str(
                        ROOT / "install/assets/defaults/hypr/colors.lua"
                    ),
                },
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(shutil.which("lua"), "Lua is unavailable")
    def test_hyprland_loader_rejects_non_six_digit_rgb_values(self):
        with tempfile.TemporaryDirectory(prefix="cloudyy-hypr-boundary-") as temp:
            root = Path(temp)
            config = root / "config/hypr"
            config.mkdir(parents=True)
            (config / "cloudyy-theme.conf").write_text(
                "$accent = rgb(0102030)\n$border = rgb(abcde)\n"
            )
            program = (
                "local c = dofile(os.getenv('CLOUDYY_TEST_COLORS_LUA')); "
                "assert(c.accent ~= 'rgb(0102030)'); "
                "assert(c.border ~= 'rgb(abcde)')"
            )
            result = subprocess.run(
                ["lua", "-e", program],
                env=os.environ | {
                    "HOME": str(root / "home"),
                    "XDG_CONFIG_HOME": str(root / "config"),
                    "CLOUDYY_TEST_COLORS_LUA": str(
                        ROOT / "install/assets/defaults/hypr/colors.lua"
                    ),
                },
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_kitty_has_one_stable_include_and_cloudyy_named_reload_helper(self):
        config = (ROOT / ".config/kitty/kitty.conf").read_text()
        helper = ROOT / ".config/kitty/cloudyy-theme-reload.sh"

        self.assertNotIn("matugen", config.lower())
        self.assertEqual(len(re.findall(
            r"^include[ \t]+current-theme\.conf[ \t]*$", config, re.MULTILINE
        )), 1)
        self.assertFalse((ROOT / ".config/kitty/matugen-reload.sh").exists())
        self.assertTrue(helper.exists())
        self.assertTrue(os.access(helper, os.X_OK))
        helper_source = helper.read_text()
        self.assertIn("kitty/current-theme.conf", helper_source)
        self.assertNotIn("matugen", helper_source.lower())

    def test_wlogout_imports_only_its_stable_curated_fragment(self):
        source = (ROOT / "bin/cloudyy-wlogout").read_text()
        self.assertIn('THEME_COLORS="${CONFIG_DIR}/cloudyy-theme.css"', source)
        self.assertNotIn("matugen", source.lower())
        for token in ("@surface_raised", "@text", "@border", "@accent", "@on_accent"):
            self.assertIn(token, source)

    def test_rofi_uses_a_complete_fixed_non_theme_baseline(self):
        config = (ROOT / ".config/rofi/config.rasi").read_text()
        baseline_path = ROOT / ".config/rofi/cloudyy-colors.rasi"
        self.assertIn('@import "cloudyy-colors.rasi"', config)
        self.assertNotIn("matugen", config.lower())
        baseline = baseline_path.read_text()
        self.assertNotIn("matugen", baseline.lower())

        used = set(re.findall(r"@([a-z][a-z0-9-]+)", config)) - {"import"}
        defined = set(re.findall(r"^\s*([a-z][a-z0-9-]+):", baseline, re.MULTILINE))
        external = {name for name in used if name not in {
            "active-background", "active-foreground", "normal-background",
            "normal-foreground", "selected-normal-background",
            "selected-normal-foreground", "selected-urgent-background",
            "selected-urgent-foreground", "urgent-background", "urgent-foreground",
            "s-act-bg", "s-border", "s-border-accent", "s-input-bg", "s-msg-bg",
            "s-text-act", "s-text-def", "s-text-dim", "s-text-urg", "s-urg-bg",
            "s-win-bg",
        }}
        self.assertEqual(external - defined, set())

    def test_yad_uses_the_curated_gtk3_boundary_and_native_names(self):
        source = (ROOT / ".config/yad/volume.css").read_text()
        self.assertIn('../gtk-3.0/cloudyy-theme.css', source)
        self.assertNotIn("matugen", source.lower())
        for token in ("@window_bg_color", "@window_fg_color", "@accent_color"):
            self.assertIn(token, source)

    def test_swayosd_and_swaync_have_no_generated_theme_dependency(self):
        osd = (ROOT / ".config/swayosd/style.css").read_text()
        swaync = (ROOT / ".config/swaync/style.css").read_text()
        colors_path = ROOT / ".config/swaync/cloudyy-colors.css"
        self.assertNotIn("matugen", osd.lower())
        self.assertNotRegex(osd, r"(?m)^\s*@import")
        self.assertIn('@import url("cloudyy-colors.css")', swaync)
        self.assertNotIn("matugen", swaync.lower())

        colors = colors_path.read_text()
        used = set(re.findall(r"@([A-Za-z][A-Za-z0-9_-]+)", swaync)) - {
            "define-color", "import",
        }
        defined = set(re.findall(r"@define-color\s+([A-Za-z][A-Za-z0-9_-]+)", colors))
        self.assertEqual(used - defined, set())

    def test_gtk_css_consumers_parse_without_native_errors(self):
        try:
            import gi

            gi.require_version("Gtk", "4.0")
            from gi.repository import Gtk
        except (ImportError, ValueError):
            self.skipTest("PyGObject GTK 4 bindings are unavailable")

        for relative in (".config/swayosd/style.css", ".config/swaync/style.css"):
            with self.subTest(path=relative):
                errors = []
                provider = Gtk.CssProvider()
                provider.connect(
                    "parsing-error",
                    lambda _provider, section, error: errors.append(
                        f"{section.get_start_location().lines + 1}: {error.message}"
                    ),
                )
                provider.load_from_path(str(ROOT / relative))
                self.assertEqual(errors, [])

    def test_named_runtime_boundaries_remain_owned_by_adapters(self):
        source = (ROOT / "lib/cloudyy-theme/adapters.sh").read_text()
        self.assertIn('directory="$config_root/gtk-${version}.0"', source)
        self.assertIn('target="$directory/cloudyy-theme.css"', source)
        for boundary in (
            "btop/themes/cloudyy.theme",
            "chrome/cloudyy-theme.css", "snippets/cloudyy-theme.css",
        ):
            self.assertIn(boundary, source)

    @unittest.skipUnless(shutil.which("nvim"), "Neovim is unavailable")
    def test_neovim_loads_the_active_curated_native_payload(self):
        with tempfile.TemporaryDirectory(prefix="cloudyy-nvim-theme-") as temp:
            state = Path(temp) / "state/cloudyy/current/theme/applications"
            state.mkdir(parents=True)
            shutil.copy2(ROOT / "themes/nord/applications/nvim.lua", state / "nvim.lua")
            command = (
                "assert(vim.o.background == 'dark'); "
                "local normal = vim.api.nvim_get_hl(0, {name='Normal'}); "
                "assert(normal.fg == 0xd8dee9); assert(normal.bg == 0x2e3440)"
            )
            result = subprocess.run(
                [
                    "nvim", "--headless", "-u", "NONE",
                    "-c", f"luafile {ROOT / '.config/nvim/lua/config/autocmds.lua'}",
                    "-c", f"lua {command}", "-c", "qa!",
                ],
                env=os.environ | {
                    "XDG_STATE_HOME": str(Path(temp) / "state"),
                    "NVIM_LOG_FILE": str(Path(temp) / "nvim.log"),
                },
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
