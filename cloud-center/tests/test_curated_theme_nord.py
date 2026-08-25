"""Cloudyy curated theme — Nord source-package contracts."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path

from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[2]
NORD_ROOT = REPO_ROOT / "themes" / "nord"

EXPECTED_APPLICATION_FILES = {
    "applications/btop.theme",
    "applications/chromium/manifest.json",
    "applications/gtk-3.css",
    "applications/gtk-4.css",
    "applications/hyprland.conf",
    "applications/kitty.conf",
    "applications/nvim.lua",
    "applications/obsidian.css",
    "applications/starship.toml",
    "applications/vscode.json",
    "applications/wlogout.css",
    "applications/zen.css",
}

EXPECTED_PACKAGE_FILES = EXPECTED_APPLICATION_FILES | {
    "theme.json",
    "wallpapers/1.jpg",
    "wallpapers/2.jpg",
    "wallpapers/3.jpg",
}

EXPECTED_WALLPAPER_SHA256 = {
    "1.jpg": "3ee4a927700d119b0abee48f8de2b37ffd8c960f9abed8929763be799c8dd766",
    "2.jpg": "6cf28f6ae2b82d62d87cdf2c11b45527b33b2069499a30fd11c61f432a5aa12a",
    "3.jpg": "c039ae7c377b4fef6f1a2b7c221aabe977cd2ffe8948fea357867a243b45d2ff",
}

OFFICIAL_NORD_COLORS = {
    "#2E3440",
    "#3B4252",
    "#434C5E",
    "#4C566A",
    "#D8DEE9",
    "#E5E9F0",
    "#ECEFF4",
    "#8FBCBB",
    "#88C0D0",
    "#81A1C1",
    "#5E81AC",
    "#BF616A",
    "#D08770",
    "#EBCB8B",
    "#A3BE8C",
    "#B48EAD",
}

EXPECTED_SEMANTIC_COLORS = {
    "background": "#2E3440",
    "surface": "#3B4252",
    "surfaceRaised": "#434C5E",
    "surfaceOverlay": "#4C566A",
    "text": "#ECEFF4",
    "textMuted": "#E5E9F0",
    "accent": "#88C0D0",
    "accentMuted": "#5E81AC",
    "accentAlt": "#8FBCBB",
    "onAccent": "#2E3440",
    "border": "#4C566A",
    "selection": "#434C5E",
    "success": "#A3BE8C",
    "warning": "#EBCB8B",
    "error": "#BF616A",
    "info": "#81A1C1",
    "shadow": "#2E3440",
}


class NordThemeContractTest(unittest.TestCase):
    def test_theme_metadata_exposes_the_approved_official_nord_mapping(self):
        path = NORD_ROOT / "theme.json"
        raw = path.read_text(encoding="utf-8")

        self.assertTrue(raw.strip(), "theme.json must be a finished asset")
        self.assertEqual(
            json.loads(raw),
            {
                "name": "Nord",
                "slug": "nord",
                "mode": "dark",
                "colors": EXPECTED_SEMANTIC_COLORS,
            },
        )

    def test_primary_text_pairs_meet_wcag_normal_text_contrast(self):
        def _luminance(color):
            channels = [int(color[index : index + 2], 16) / 255 for index in (1, 3, 5)]
            linear = [
                channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4
                for channel in channels
            ]
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]

        def _contrast(first, second):
            lighter, darker = sorted((_luminance(first), _luminance(second)), reverse=True)
            return (lighter + 0.05) / (darker + 0.05)

        for foreground, background in (
            ("#ECEFF4", "#2E3440"),
            ("#ECEFF4", "#3B4252"),
            ("#2E3440", "#88C0D0"),
        ):
            with self.subTest(foreground=foreground, background=background):
                self.assertGreaterEqual(_contrast(foreground, background), 4.5)

    def test_application_inventory_contains_finished_native_assets(self):
        package_files = {
            path.relative_to(NORD_ROOT).as_posix()
            for path in NORD_ROOT.rglob("*")
            if path.is_file() or path.is_symlink()
        }

        self.assertEqual(package_files, EXPECTED_PACKAGE_FILES)
        self.assertFalse((NORD_ROOT / "applications" / "rofi.rasi").exists())

        for relative_path in sorted(EXPECTED_PACKAGE_FILES):
            path = NORD_ROOT / relative_path
            with self.subTest(path=relative_path):
                self.assertTrue(path.is_file())
                self.assertFalse(path.is_symlink())
            if relative_path not in EXPECTED_APPLICATION_FILES:
                continue
            raw = path.read_text(encoding="utf-8")
            with self.subTest(path=relative_path):
                self.assertTrue(raw.strip(), f"{relative_path} must be finished")
                self.assertNotIn("{{", raw)
                self.assertNotIn("{%", raw)
                self.assertNotIn("<*", raw)

    def test_authored_hex_colors_are_opaque_official_nord_values(self):
        for path in sorted((NORD_ROOT / "applications").rglob("*")):
            if not path.is_file():
                continue
            raw = path.read_text(encoding="utf-8")
            if path.name == "manifest.json" and path.parent.name == "chromium":
                continue
            colors = {value.upper() for value in re.findall(r"#[0-9a-fA-F]{6}\b", raw)}
            colors.update(
                f"#{value.upper()}" for value in re.findall(r"\brgb\(([0-9a-fA-F]{6})\)", raw)
            )
            alpha_colors = re.findall(r"#[0-9a-fA-F]{8}\b", raw)
            with self.subTest(path=path.relative_to(NORD_ROOT).as_posix()):
                self.assertFalse(alpha_colors, "theme assets must not own alpha")
                self.assertNotIn("rgba(", raw.lower())
                self.assertTrue(colors, "native asset must contain explicit colors")
                self.assertLessEqual(colors, OFFICIAL_NORD_COLORS)

    def test_wallpapers_are_the_ordered_decodable_user_assets(self):
        wallpapers = sorted(
            (path for path in (NORD_ROOT / "wallpapers").iterdir() if path.is_file()),
            key=lambda path: int(path.stem),
        )

        self.assertEqual([path.name for path in wallpapers], ["1.jpg", "2.jpg", "3.jpg"])
        for path in wallpapers:
            self.assertFalse(path.is_symlink())
            self.assertGreater(int(path.stem), 0)
            self.assertIn(path.suffix.lower(), {".jpg", ".jpeg", ".png", ".webp"})
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), EXPECTED_WALLPAPER_SHA256[path.name])
            with Image.open(path) as image:
                image.verify()

    def test_hyprland_payload_exposes_semantic_colors_without_properties(self):
        path = NORD_ROOT / "applications" / "hyprland.conf"
        assignments = []
        for line in path.read_text(encoding="utf-8").splitlines():
            match = re.fullmatch(r"\$([a-z_]+)\s*=\s*rgb\(([0-9a-fA-F]{6})\)", line)
            self.assertIsNotNone(match, f"non-color Hyprland directive: {line!r}")
            assignments.append(match.groups())
        expected = {
            re.sub(r"(?<!^)(?=[A-Z])", "_", role).lower(): value.removeprefix("#").lower()
            for role, value in EXPECTED_SEMANTIC_COLORS.items()
        }

        self.assertEqual(len(assignments), len(dict(assignments)), "duplicate Hyprland color assignment")
        self.assertEqual(dict(assignments), expected)

    def test_kitty_payload_uses_the_finished_nord_terminal_mapping(self):
        path = NORD_ROOT / "applications" / "kitty.conf"
        directive_pairs = []
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, value = line.split(maxsplit=1)
            directive_pairs.append((key, value.upper()))
        self.assertEqual(len(directive_pairs), len(dict(directive_pairs)), "duplicate Kitty directive")
        directives = dict(directive_pairs)

        self.assertEqual(
            directives,
            {
                "background": "#2E3440",
                "foreground": "#D8DEE9",
                "cursor": "#D8DEE9",
                "cursor_text_color": "#2E3440",
                "selection_background": "#4C566A",
                "selection_foreground": "#ECEFF4",
                "url_color": "#88C0D0",
                "color0": "#3B4252",
                "color1": "#BF616A",
                "color2": "#A3BE8C",
                "color3": "#EBCB8B",
                "color4": "#81A1C1",
                "color5": "#B48EAD",
                "color6": "#88C0D0",
                "color7": "#E5E9F0",
                "color8": "#4C566A",
                "color9": "#BF616A",
                "color10": "#A3BE8C",
                "color11": "#EBCB8B",
                "color12": "#81A1C1",
                "color13": "#B48EAD",
                "color14": "#8FBCBB",
                "color15": "#ECEFF4",
            },
        )

    def test_btop_payload_has_only_the_native_color_contract(self):
        path = NORD_ROOT / "applications" / "btop.theme"
        raw = path.read_text(encoding="utf-8")
        assignment_pairs = []
        for line in raw.splitlines():
            match = re.fullmatch(r'theme\[([a-z_]+)\]="(#[0-9A-Fa-f]{6})"', line)
            self.assertIsNotNone(match, f"non-color btop directive: {line!r}")
            assignment_pairs.append(match.groups())
        self.assertEqual(len(assignment_pairs), len(dict(assignment_pairs)), "duplicate btop color assignment")
        assignments = dict(assignment_pairs)

        self.assertEqual(
            set(assignments),
            {
                "main_bg", "main_fg", "title", "hi_fg", "selected_bg", "selected_fg",
                "inactive_fg", "graph_text", "meter_bg", "proc_misc", "cpu_box", "mem_box",
                "net_box", "proc_box", "div_line", "temp_start", "temp_mid", "temp_end",
                "cpu_start", "cpu_mid", "cpu_end", "free_start", "free_mid", "free_end",
                "cached_start", "cached_mid", "cached_end", "available_start", "available_mid",
                "available_end", "used_start", "used_mid", "used_end", "download_start",
                "download_mid", "download_end", "upload_start", "upload_mid", "upload_end",
            },
        )

    def test_starship_payload_keeps_the_prompt_baseline_and_uses_nord_palette(self):
        path = NORD_ROOT / "applications" / "starship.toml"
        raw = path.read_text(encoding="utf-8")
        data = tomllib.loads(raw)
        baseline_path = REPO_ROOT / "lib" / "cloudyy-theme" / "starship-baseline.toml"
        baseline = tomllib.loads(baseline_path.read_text(encoding="utf-8"))

        self.assertNotIn("matugen", raw.lower())
        self.assertEqual(data["palette"], "nord")
        self.assertEqual(
            data["palettes"]["nord"],
            {
                "surface": "#434C5E",
                "text": "#ECEFF4",
                "text_muted": "#E5E9F0",
                "primary": "#88C0D0",
                "secondary": "#8FBCBB",
                "tertiary": "#81A1C1",
                "error": "#BF616A",
                "warning": "#EBCB8B",
                "outline": "#4C566A",
                "format": baseline["palettes"]["cloudyy_baseline"]["format"],
                "right_format": baseline["palettes"]["cloudyy_baseline"]["right_format"],
            },
        )
        self.assertEqual(set(data), set(baseline))
        for key in set(baseline) - {"palette", "palettes"}:
            with self.subTest(section=key):
                self.assertEqual(data[key], baseline[key])

    def test_gtk_payloads_define_only_the_owned_color_contract(self):
        expected_names = {
            "accent_color", "accent_fg_color", "accent_bg_color", "window_bg_color",
            "window_fg_color", "headerbar_bg_color", "headerbar_fg_color", "popover_bg_color",
            "popover_fg_color", "view_bg_color", "view_fg_color", "card_bg_color",
            "card_fg_color", "sidebar_bg_color", "sidebar_fg_color", "sidebar_border_color",
            "sidebar_backdrop_color", "text_primary", "text_secondary", "text_disabled",
            "button_bg_color", "button_fg_color", "button_border_color", "error_color",
            "warning_color", "success_color",
        }
        for filename in ("gtk-3.css", "gtk-4.css"):
            raw = (NORD_ROOT / "applications" / filename).read_text(encoding="utf-8")
            definition_pairs = []
            for line in raw.splitlines():
                match = re.fullmatch(r"@define-color ([a-z_]+) (#[0-9A-Fa-f]{6});", line)
                self.assertIsNotNone(match, f"non-color GTK directive: {line!r}")
                definition_pairs.append(match.groups())
            with self.subTest(filename=filename):
                self.assertEqual(
                    len(definition_pairs), len(dict(definition_pairs)), "duplicate GTK color definition"
                )
                definitions = dict(definition_pairs)
                self.assertEqual(set(definitions), expected_names)

    def test_wlogout_payload_is_a_color_definition_fragment(self):
        raw = (NORD_ROOT / "applications" / "wlogout.css").read_text(encoding="utf-8")
        definition_pairs = []
        for line in raw.splitlines():
            match = re.fullmatch(r"@define-color ([a-z_]+) (#[0-9A-Fa-f]{6});", line)
            self.assertIsNotNone(match, f"non-color Wlogout directive: {line!r}")
            definition_pairs.append(match.groups())
        self.assertEqual(
            len(definition_pairs), len(dict(definition_pairs)), "duplicate Wlogout color definition"
        )
        definitions = dict(definition_pairs)

        self.assertEqual(
            definitions,
            {
                "background": "#2E3440",
                "surface": "#3B4252",
                "surface_raised": "#434C5E",
                "text": "#ECEFF4",
                "text_muted": "#E5E9F0",
                "accent": "#88C0D0",
                "on_accent": "#2E3440",
                "border": "#4C566A",
            },
        )
        self.assertNotIn("{", raw)

    def test_css_consumers_ship_colors_without_layout_or_remote_content(self):
        expected_contracts = {
            "zen.css": {
                (":root",): {
                    "color-scheme", "--zen-primary-color", "--zen-colors-primary",
                    "--zen-colors-secondary", "--zen-colors-tertiary", "--zen-colors-border",
                    "--toolbarbutton-icon-fill", "--lwt-text-color", "--toolbar-field-color",
                    "--tab-selected-textcolor", "--toolbar-field-focus-color", "--toolbar-color",
                    "--newtab-text-primary-color", "--arrowpanel-color", "--arrowpanel-background",
                    "--panel-text-color", "--panel-background-color",
                    "--toolbar-field-text-color-focus", "--toolbar-field-background-color-focus",
                    "--sidebar-text-color", "--lwt-sidebar-text-color",
                    "--lwt-sidebar-background-color", "--toolbar-bgcolor",
                    "--newtab-background-color", "--zen-themed-toolbar-bg",
                    "--zen-main-browser-background", "--toolbox-bgcolor-inactive",
                },
                ("#TabsToolbar", "hbox#titlebar", "#zen-appcontent-navbar-container"): {
                    "background-color",
                },
                (".urlbar-background", "#zen-workspaces-button", ".sidebar-placesTree"): {
                    "background-color",
                },
            },
            "obsidian.css": {
                (".theme-dark",): {
                    "--background-primary", "--background-primary-alt", "--background-secondary",
                    "--background-secondary-alt", "--titlebar-background",
                    "--titlebar-background-focused", "--titlebar-text-color",
                    "--background-modifier-border", "--background-modifier-border-focus",
                    "--background-modifier-border-hover", "--background-modifier-hover",
                    "--background-modifier-active-hover", "--background-modifier-success",
                    "--background-modifier-error", "--text-normal", "--text-muted", "--text-faint",
                    "--text-on-accent", "--text-selection", "--interactive-accent",
                    "--interactive-accent-hover", "--interactive-normal", "--interactive-hover",
                    "--interactive-success", "--color-red", "--color-orange", "--color-yellow",
                    "--color-green", "--color-cyan", "--color-blue", "--color-purple",
                    "--color-pink", "--h1-color", "--h2-color", "--h3-color", "--h4-color",
                },
            },
        }
        block_pattern = re.compile(r"([^{}]+)\{([^{}]*)\}", re.DOTALL)
        for filename, expected in expected_contracts.items():
            raw = (NORD_ROOT / "applications" / filename).read_text(encoding="utf-8")
            with self.subTest(filename=filename):
                blocks = list(block_pattern.finditer(raw))
                self.assertFalse(block_pattern.sub("", raw).strip(), "content outside CSS blocks")
                actual = {}
                for block in blocks:
                    selectors = tuple(part.strip() for part in block.group(1).split(","))
                    properties = []
                    for declaration in block.group(2).split(";"):
                        if not declaration.strip():
                            continue
                        name, separator, value = declaration.strip().partition(":")
                        self.assertEqual(separator, ":", f"invalid declaration: {declaration!r}")
                        self.assertTrue(value.strip(), f"missing value for {name}")
                        properties.append(name)
                    self.assertNotIn(selectors, actual, f"duplicate selector block: {selectors}")
                    self.assertEqual(len(properties), len(set(properties)), "duplicate CSS property")
                    actual[selectors] = set(properties)
                self.assertEqual(actual, expected)

    def test_neovim_payload_is_a_loadable_color_only_module(self):
        path = NORD_ROOT / "applications" / "nvim.lua"
        self.assertTrue(path.read_text(encoding="utf-8").strip(), "nvim.lua must be finished")
        luac = shutil.which("luac")
        lua = shutil.which("lua")
        if not luac or not lua:
            self.skipTest("Lua syntax tools are unavailable")

        subprocess.run([luac, "-p", str(path)], check=True, capture_output=True, text=True)
        script = """
local theme = dofile(arg[0])
assert(theme.name == "Nord")
assert(theme.mode == "dark")
local palette_count = 0
for name, value in pairs(theme.palette) do
  palette_count = palette_count + 1
  assert(name:match("^nord%d+$"))
  assert(value:match("^#[0-9A-F]+$"))
end
assert(palette_count == 16)
local highlight_count = 0
for _, spec in pairs(theme.highlights) do
  highlight_count = highlight_count + 1
  for key, value in pairs(spec) do
    assert(key == "fg" or key == "bg" or key == "sp")
    assert(theme.palette[value] ~= nil)
  end
end
assert(highlight_count >= 30)
"""
        subprocess.run([lua, "-e", script, str(path)], check=True, capture_output=True, text=True)

    def test_vscode_payload_owns_only_finished_workbench_colors(self):
        path = NORD_ROOT / "applications" / "vscode.json"
        raw = path.read_text(encoding="utf-8")
        self.assertTrue(raw.strip(), "vscode.json must be finished")
        pairs = []

        def _collect_pairs(items):
            pairs.extend(key for key, _value in items)
            return dict(items)

        data = json.loads(raw, object_pairs_hook=_collect_pairs)
        self.assertEqual(set(data), {"workbench.colorCustomizations"})
        self.assertEqual(len(pairs), len(set(pairs)), "vscode.json must not contain duplicate keys")

        colors = data["workbench.colorCustomizations"]
        self.assertGreaterEqual(len(colors), 50)
        opacity_policy_keys = {
            "button.background",
            "editor.findMatchBackground",
            "editor.findMatchHighlightBackground",
            "editor.inactiveSelectionBackground",
            "editor.selectionBackground",
            "editor.selectionHighlightBackground",
            "editor.wordHighlightBackground",
            "editor.wordHighlightStrongBackground",
            "editorBracketMatch.background",
            "editorIndentGuide.background",
            "editorWhitespace.foreground",
            "gitDecoration.ignoredResourceForeground",
            "input.placeholderForeground",
            "panelTitle.activeBorder",
            "selection.background",
            "tab.activeBorderTop",
            "tab.border",
            "tab.inactiveForeground",
            "titleBar.inactiveForeground",
        }
        self.assertTrue(
            set(colors).isdisjoint(opacity_policy_keys),
            "alpha-dependent official-port keys belong to the permanent VS Code baseline",
        )
        self.assertEqual(
            {key: colors[key] for key in (
                "activityBar.background", "activityBar.activeBorder", "badge.background",
                "button.hoverBackground", "button.foreground", "editor.background", "editor.foreground",
                "editorLineNumber.foreground", "editorCursor.foreground",
                "editorError.foreground", "editorWarning.foreground", "editorInfo.foreground",
                "statusBar.background", "terminal.ansiRed", "terminal.ansiGreen", "terminal.ansiBlue",
                "terminal.ansiCyan", "terminal.ansiBrightWhite",
            )},
            {
                "activityBar.background": "#2E3440",
                "activityBar.activeBorder": "#88C0D0",
                "badge.background": "#88C0D0",
                "button.hoverBackground": "#8FBCBB",
                "button.foreground": "#2E3440",
                "editor.background": "#2E3440",
                "editor.foreground": "#D8DEE9",
                "editorLineNumber.foreground": "#4C566A",
                "editorCursor.foreground": "#D8DEE9",
                "editorError.foreground": "#BF616A",
                "editorWarning.foreground": "#EBCB8B",
                "editorInfo.foreground": "#81A1C1",
                "statusBar.background": "#3B4252",
                "terminal.ansiRed": "#BF616A",
                "terminal.ansiGreen": "#A3BE8C",
                "terminal.ansiBlue": "#81A1C1",
                "terminal.ansiCyan": "#88C0D0",
                "terminal.ansiBrightWhite": "#ECEFF4",
            },
        )

    def test_chromium_payload_is_an_exact_color_only_theme_manifest(self):
        path = NORD_ROOT / "applications" / "chromium" / "manifest.json"
        raw = path.read_text(encoding="utf-8")
        self.assertTrue(raw.strip(), "Chromium manifest must be finished")
        data = json.loads(raw)

        self.assertEqual(set(data), {"name", "version", "manifest_version", "theme"})
        self.assertEqual(data["name"], "Cloudyy Nord")
        self.assertEqual(data["version"], "1.0.0")
        self.assertEqual(data["manifest_version"], 3)
        self.assertEqual(set(data["theme"]), {"colors"})

        colors = data["theme"]["colors"]
        self.assertEqual(
            set(colors),
            {
                "background_tab", "background_tab_inactive", "background_tab_incognito",
                "background_tab_incognito_inactive", "bookmark_text", "button_background",
                "frame", "frame_inactive", "frame_incognito", "frame_incognito_inactive",
                "ntp_background", "ntp_header", "ntp_link", "ntp_text", "omnibox_background",
                "omnibox_text", "tab_background_text", "tab_background_text_inactive",
                "tab_background_text_incognito", "tab_background_text_incognito_inactive",
                "tab_text", "toolbar", "toolbar_button_icon", "toolbar_text",
            },
        )
        official_rgb = {
            tuple(int(color[index : index + 2], 16) for index in (1, 3, 5))
            for color in OFFICIAL_NORD_COLORS
        }
        for key, value in colors.items():
            with self.subTest(color=key):
                self.assertIs(type(value), list)
                self.assertEqual(len(value), 3)
                self.assertIn(tuple(value), official_rgb)

        for active, inactive in (
            ("background_tab", "background_tab_inactive"),
            ("background_tab_incognito", "background_tab_incognito_inactive"),
            ("frame", "frame_inactive"),
            ("frame_incognito", "frame_incognito_inactive"),
            ("tab_background_text", "tab_background_text_inactive"),
            ("tab_background_text_incognito", "tab_background_text_incognito_inactive"),
        ):
            self.assertEqual(colors[active], colors[inactive])

    def test_chromium_accepts_the_manifest_without_opening_a_profile(self):
        chromium = shutil.which("chromium")
        if not chromium:
            self.skipTest("Chromium is unavailable")

        source = NORD_ROOT / "applications" / "chromium"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            theme = root / "theme"
            shutil.copytree(source, theme)
            environment = {
                "HOME": str(root / "home"),
                "XDG_CONFIG_HOME": str(root / "config"),
                "XDG_CACHE_HOME": str(root / "cache"),
                "PATH": "/usr/bin:/bin",
            }
            result = subprocess.run(
                [chromium, f"--pack-extension={theme}"],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
                env=environment,
            )

            if "crashpad" in result.stderr.lower() and "operation not permitted" in result.stderr.lower():
                self.skipTest("Chromium pack validation is blocked by the test sandbox")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((root / "theme.crx").is_file())


if __name__ == "__main__":
    unittest.main()
