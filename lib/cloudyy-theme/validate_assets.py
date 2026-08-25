#!/usr/bin/env python3
"""Static, color-only contracts for shipped Cloudyy theme payloads."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path


HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
RGB = re.compile(r"^rgb\([0-9A-Fa-f]{6}\)$")
GTK_KEYS = {
    "accent_color", "accent_fg_color", "accent_bg_color", "window_bg_color", "window_fg_color",
    "headerbar_bg_color", "headerbar_fg_color", "popover_bg_color", "popover_fg_color", "view_bg_color",
    "view_fg_color", "card_bg_color", "card_fg_color", "sidebar_bg_color", "sidebar_fg_color",
    "sidebar_border_color", "sidebar_backdrop_color", "text_primary", "text_secondary", "text_disabled",
    "button_bg_color", "button_fg_color", "button_border_color", "error_color", "warning_color", "success_color",
}
WLOGOUT_KEYS = {"background", "surface", "surface_raised", "text", "text_muted", "accent", "on_accent", "border"}
KITTY_KEYS = {"background", "foreground", "cursor", "cursor_text_color", "selection_background", "selection_foreground", "url_color", *(f"color{i}" for i in range(16))}
BTOP_KEYS = "main_bg main_fg title hi_fg selected_bg selected_fg inactive_fg graph_text meter_bg proc_misc cpu_box mem_box net_box proc_box div_line temp_start temp_mid temp_end cpu_start cpu_mid cpu_end free_start free_mid free_end cached_start cached_mid cached_end available_start available_mid available_end used_start used_mid used_end download_start download_mid download_end upload_start upload_mid upload_end".split()
CHROMIUM_KEYS = "background_tab background_tab_inactive background_tab_incognito background_tab_incognito_inactive bookmark_text button_background frame frame_inactive frame_incognito frame_incognito_inactive ntp_background ntp_header ntp_link ntp_text omnibox_background omnibox_text tab_background_text tab_background_text_inactive tab_background_text_incognito tab_background_text_incognito_inactive tab_text toolbar toolbar_button_icon toolbar_text".split()
VSCODE_KEYS = """activityBar.activeBackground activityBar.activeBorder activityBar.background activityBar.foreground activityBar.inactiveForeground activityBarBadge.background activityBarBadge.foreground badge.background badge.foreground button.foreground button.hoverBackground button.secondaryBackground button.secondaryForeground button.secondaryHoverBackground dropdown.background dropdown.border dropdown.foreground editor.background editor.foreground editor.lineHighlightBackground editorBracketMatch.border editorCursor.foreground editorError.foreground editorGutter.addedBackground editorGutter.background editorGutter.deletedBackground editorGutter.modifiedBackground editorHint.foreground editorHoverWidget.background editorHoverWidget.border editorHoverWidget.foreground editorIndentGuide.activeBackground editorInfo.foreground editorLineNumber.activeForeground editorLineNumber.foreground editorSuggestWidget.background editorSuggestWidget.border editorSuggestWidget.foreground editorSuggestWidget.highlightForeground editorSuggestWidget.selectedBackground editorWarning.foreground editorWidget.background editorWidget.border editorWidget.foreground errorForeground focusBorder foreground gitDecoration.conflictingResourceForeground gitDecoration.deletedResourceForeground gitDecoration.modifiedResourceForeground gitDecoration.submoduleResourceForeground gitDecoration.untrackedResourceForeground input.background input.border input.foreground inputOption.activeBackground inputOption.activeBorder inputOption.activeForeground list.activeSelectionBackground list.activeSelectionForeground list.errorForeground list.highlightForeground list.hoverBackground list.hoverForeground list.inactiveSelectionBackground list.inactiveSelectionForeground list.warningForeground notificationCenterHeader.background notificationCenterHeader.foreground notifications.background notifications.border notifications.foreground panel.background panel.border panelTitle.activeForeground panelTitle.inactiveForeground progressBar.background sideBar.background sideBar.border sideBar.foreground sideBarSectionHeader.background sideBarSectionHeader.foreground statusBar.background statusBar.debuggingBackground statusBar.debuggingForeground statusBar.foreground statusBar.noFolderBackground statusBar.noFolderForeground statusBarItem.activeBackground statusBarItem.errorForeground statusBarItem.hoverBackground statusBarItem.warningForeground tab.activeBackground tab.activeForeground tab.inactiveBackground terminal.ansiBlack terminal.ansiBlue terminal.ansiBrightBlack terminal.ansiBrightBlue terminal.ansiBrightCyan terminal.ansiBrightGreen terminal.ansiBrightMagenta terminal.ansiBrightRed terminal.ansiBrightWhite terminal.ansiBrightYellow terminal.ansiCyan terminal.ansiGreen terminal.ansiMagenta terminal.ansiRed terminal.ansiWhite terminal.ansiYellow terminal.background terminal.foreground terminalCursor.background terminalCursor.foreground textLink.activeForeground textLink.foreground titleBar.activeBackground titleBar.activeForeground titleBar.inactiveBackground""".split()
CSS_CONTRACTS = {
    # No vesktop.css contract: Vesktop has been removed from this system.
    "obsidian.css": {".theme-dark": "--background-primary --background-primary-alt --background-secondary --background-secondary-alt --titlebar-background --titlebar-background-focused --titlebar-text-color --background-modifier-border --background-modifier-border-focus --background-modifier-border-hover --background-modifier-hover --background-modifier-active-hover --background-modifier-success --background-modifier-error --text-normal --text-muted --text-faint --text-on-accent --text-selection --interactive-accent --interactive-accent-hover --interactive-normal --interactive-hover --interactive-success --color-red --color-orange --color-yellow --color-green --color-cyan --color-blue --color-purple --color-pink --h1-color --h2-color --h3-color --h4-color".split()},
    "zen.css": {
        ":root": "color-scheme --zen-primary-color --zen-colors-primary --zen-colors-secondary --zen-colors-tertiary --zen-colors-border --toolbarbutton-icon-fill --lwt-text-color --toolbar-field-color --tab-selected-textcolor --toolbar-field-focus-color --toolbar-color --newtab-text-primary-color --arrowpanel-color --arrowpanel-background --panel-text-color --panel-background-color --toolbar-field-text-color-focus --toolbar-field-background-color-focus --sidebar-text-color --lwt-sidebar-text-color --lwt-sidebar-background-color --toolbar-bgcolor --newtab-background-color --zen-themed-toolbar-bg --zen-main-browser-background --toolbox-bgcolor-inactive".split(),
        "#TabsToolbar,hbox#titlebar,#zen-appcontent-navbar-container": ["background-color"],
        ".urlbar-background,#zen-workspaces-button,.sidebar-placesTree": ["background-color"],
    },
}


def fail(message: str) -> None:
    print(f"cloudyy-theme: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"invalid JSON in {path.name}: {error}")


def validate_simple_pairs(path: Path, keys: set[str], pattern: re.Pattern[str], label: str) -> None:
    pairs = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        match = pattern.fullmatch(line)
        if not match:
            fail(f"{label} contains non-color content")
        pairs.append(match.groups())
    if len(pairs) != len(dict(pairs)) or set(dict(pairs)) != keys:
        fail(f"{label} does not match its owned-field contract")


def validate_css(path: Path, contract: dict[str, list[str]], mode: str) -> None:
    raw = path.read_text(encoding="utf-8")
    blocks = list(re.finditer(r"([^{}]+)\{([^{}]*)\}", raw, re.DOTALL))
    if not blocks or re.sub(r"([^{}]+)\{([^{}]*)\}", "", raw).strip():
        fail(f"{path.name} contains non-color CSS content")
    actual: dict[str, list[str]] = {}
    for block in blocks:
        selector = ",".join(piece.strip() for piece in block.group(1).split(","))
        declarations = []
        for declaration in block.group(2).split(";"):
            if not declaration.strip():
                continue
            key, separator, value = declaration.strip().partition(":")
            if not separator or not key or not value.strip():
                fail(f"{path.name} has an invalid CSS declaration")
            value = value.strip().removesuffix("!important").strip()
            if key == "color-scheme":
                if value != mode:
                    fail(f"{path.name} has a mismatched color scheme")
            elif not HEX.fullmatch(value):
                fail(f"{path.name} has a non-RGB CSS value")
            declarations.append(key)
        if selector in actual or len(declarations) != len(set(declarations)):
            fail(f"{path.name} repeats a selector or owned field")
        actual[selector] = declarations
    if set(actual) != set(contract) or any(set(actual[key]) != set(contract[key]) for key in contract):
        fail(f"{path.name} does not match its owned-field contract")


def _lua_tokens(raw: str) -> list[tuple[str, str]]:
    token = re.compile(r'\s*(?:(--[^\n]*)|([A-Za-z_][A-Za-z0-9_]*)|("(?:[^"\\]|\\.)*")|([{}=,]))')
    result = []
    position = 0
    while position < len(raw):
        if not raw[position:].strip():
            break
        match = token.match(raw, position)
        if not match:
            fail("Neovim Lua is not a static literal table")
        position = match.end()
        if match.group(1):
            continue
        if match.group(2):
            result.append(("identifier", match.group(2)))
        elif match.group(3):
            result.append(("string", match.group(3)))
        else:
            result.append(("symbol", match.group(4)))
    return result


def _parse_lua_table(tokens: list[tuple[str, str]], index: int) -> tuple[dict[str, object], int]:
    if index >= len(tokens) or tokens[index] != ("symbol", "{"):
        fail("Neovim Lua is not a static literal table")
    index += 1
    table: dict[str, object] = {}
    while index < len(tokens) and tokens[index] != ("symbol", "}"):
        if tokens[index][0] != "identifier" or index + 1 >= len(tokens) or tokens[index + 1] != ("symbol", "="):
            fail("Neovim Lua table has an invalid field")
        key = tokens[index][1]
        index += 2
        if index >= len(tokens):
            fail("Neovim Lua table has an incomplete field")
        if tokens[index] == ("symbol", "{"):
            value, index = _parse_lua_table(tokens, index)
        elif tokens[index][0] == "string":
            try:
                value = json.loads(tokens[index][1])
            except json.JSONDecodeError:
                fail("Neovim Lua has an invalid string")
            index += 1
        else:
            fail("Neovim Lua values must be literal strings or tables")
        if key in table:
            fail("Neovim Lua repeats a field")
        table[key] = value
        if index < len(tokens) and tokens[index] == ("symbol", ","):
            index += 1
    if index >= len(tokens) or tokens[index] != ("symbol", "}"):
        fail("Neovim Lua has an unclosed table")
    return table, index + 1


def validate_lua(path: Path, name: str, mode: str) -> None:
    luac = shutil.which("luac")
    if luac and subprocess.run([luac, "-p", str(path)], capture_output=True, text=True).returncode:
        fail("invalid Neovim Lua")
    tokens = _lua_tokens(path.read_text(encoding="utf-8"))
    if not tokens or tokens[0] != ("identifier", "return"):
        fail("Neovim Lua must return a static color-only table")
    theme, index = _parse_lua_table(tokens, 1)
    if index != len(tokens) or set(theme) != {"name", "mode", "palette", "highlights"}:
        fail("Neovim Lua does not match the owned table schema")
    if theme["name"] != name or theme["mode"] != mode:
        fail("Neovim Lua does not match theme metadata")
    palette = theme["palette"]
    if not isinstance(palette, dict) or not palette or not all(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key) and isinstance(value, str) and HEX.fullmatch(value) for key, value in palette.items()):
        fail("Neovim Lua does not contain the complete palette")
    highlights = theme["highlights"]
    if not isinstance(highlights, dict) or not highlights:
        fail("Neovim Lua must contain static highlights")
    for highlight, specification in highlights.items():
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", highlight) or not isinstance(specification, dict) or not specification or set(specification) - {"fg", "bg", "sp"}:
            fail("Neovim Lua contains an unowned highlight")
        if not all(isinstance(value, str) and value in palette for value in specification.values()):
            fail("Neovim Lua references an unknown palette color")


def validate_assets(package: Path, slug: str, name: str, mode: str) -> None:
    applications = package / "applications"
    validate_simple_pairs(applications / "hyprland.conf", {"background", "surface", "surface_raised", "surface_overlay", "text", "text_muted", "accent", "accent_muted", "accent_alt", "on_accent", "border", "selection", "success", "warning", "error", "info", "shadow"}, re.compile(r"\$([a-z_]+)\s*=\s*(rgb\([0-9A-Fa-f]{6}\))"), "Hyprland")
    validate_simple_pairs(applications / "kitty.conf", KITTY_KEYS, re.compile(r"([a-z_0-9]+)\s+(#[0-9A-Fa-f]{6})"), "Kitty")
    validate_simple_pairs(applications / "btop.theme", set(BTOP_KEYS), re.compile(r'theme\[([a-z_]+)\]="(#[0-9A-Fa-f]{6})"'), "btop")
    for filename in ("gtk-3.css", "gtk-4.css"):
        validate_simple_pairs(applications / filename, GTK_KEYS, re.compile(r"@define-color ([a-z_]+) (#[0-9A-Fa-f]{6});"), filename)
    validate_simple_pairs(applications / "wlogout.css", WLOGOUT_KEYS, re.compile(r"@define-color ([a-z_]+) (#[0-9A-Fa-f]{6});"), "Wlogout")
    for filename, contract in CSS_CONTRACTS.items():
        validate_css(applications / filename, contract, mode)
    validate_lua(applications / "nvim.lua", name, mode)

    vscode = read_json(applications / "vscode.json")
    colors = vscode.get("workbench.colorCustomizations") if isinstance(vscode, dict) and set(vscode) == {"workbench.colorCustomizations"} else None
    if not isinstance(colors, dict) or set(colors) != set(VSCODE_KEYS) or not all(isinstance(value, str) and HEX.fullmatch(value) for value in colors.values()):
        fail("VS Code does not match its owned-field RGB contract")
    chromium = read_json(applications / "chromium/manifest.json")
    colors = chromium.get("theme", {}).get("colors") if isinstance(chromium, dict) and isinstance(chromium.get("theme"), dict) else None
    if (not isinstance(chromium, dict) or set(chromium) != {"name", "version", "manifest_version", "theme"} or chromium.get("name") != f"Cloudyy {name}" or chromium.get("version") != "1.0.0" or chromium.get("manifest_version") != 3 or not isinstance(chromium.get("theme"), dict) or set(chromium["theme"]) != {"colors"} or not isinstance(colors, dict) or set(colors) != set(CHROMIUM_KEYS) or not all(isinstance(value, list) and len(value) == 3 and all(type(channel) is int and 0 <= channel <= 255 for channel in value) for value in colors.values())):
        fail("Chromium does not match its owned-field RGB contract")

    try:
        data = tomllib.loads((applications / "starship.toml").read_text(encoding="utf-8"))
        baseline = tomllib.loads((Path(__file__).with_name("starship-baseline.toml")).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
        fail(f"invalid Starship TOML: {error}")
    palette = data.get("palettes", {}).get(slug)
    colors = {"surface", "text", "text_muted", "primary", "secondary", "tertiary", "error", "warning", "outline"}
    if set(data) != set(baseline) or data.get("palette") != slug or set(data.get("palettes", {})) != {slug} or not isinstance(palette, dict) or set(palette) != colors | {"format", "right_format"} or not all(isinstance(palette[key], str) and HEX.fullmatch(palette[key]) for key in colors) or palette["format"] != baseline["palettes"]["cloudyy_baseline"]["format"] or palette["right_format"] != baseline["palettes"]["cloudyy_baseline"]["right_format"] or any(data[key] != baseline[key] for key in set(baseline) - {"palette", "palettes"}):
        fail("Starship does not match its color-only invariant contract")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit("usage: validate_assets.py <package> <slug> <name> <mode>")
    validate_assets(Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4])
