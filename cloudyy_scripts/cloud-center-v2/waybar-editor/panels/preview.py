"""
waybar-editor/panels/preview.py
Right panel: WebKitGTK live preview of the waybar style.
"""
from __future__ import annotations

import logging
import re
from pathlib import Path

import gi
from gi.repository import GLib, Gtk

from models import Preset
from parser import collect_css_vars

log = logging.getLogger(__name__)

_WEBKIT_OK = False
_WebKitLib = None
try:
    gi.require_version("WebKit", "6.0")
    from gi.repository import WebKit as _WebKitLib
    _WEBKIT_OK = True
except Exception:
    try:
        gi.require_version("WebKit2", "4.1")
        from gi.repository import WebKit2 as _WebKitLib
        _WEBKIT_OK = True
    except Exception:
        log.warning("WebKitGTK not available — live preview disabled")


# ── CSS transformer ───────────────────────────────────────────────────────────

_DEFINE_COLOR = re.compile(r"@define-color\s+(\w+)\s+(.+?)\s*;")
_IMPORT_RE    = re.compile(r'@import\s+url\(["\']?[^"\')\s]+["\']?\)\s*;')
_ALPHA_FN     = re.compile(r'alpha\(@(\w+),\s*([\d.]+)\)')
_COLOR_REF    = re.compile(r"@([\w]+)")


def _resolve_color(name: str, vars_: dict[str, str], depth: int = 0) -> str:
    """Recursively resolve a color variable name to a concrete value."""
    if depth > 8 or name not in vars_:
        return vars_.get(name, "")
    val = vars_[name]
    # One level of @reference inside the value (e.g. @define-color x @y)
    return _COLOR_REF.sub(
        lambda m: _resolve_color(m.group(1), vars_, depth + 1) or m.group(0),
        val,
    )


def _color_to_rgba(color: str, alpha: float) -> str:
    """Convert a CSS color + alpha float to rgba() or color-mix() fallback."""
    color = color.strip()
    if color.startswith("#"):
        h = color.lstrip("#")
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        if len(h) == 6:
            r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
            return f"rgba({r}, {g}, {b}, {alpha})"
    return f"color-mix(in srgb, {color} {alpha * 100:.0f}%, transparent)"


def transform_css_for_browser(css: str, style_path: Path | None = None) -> str:
    """Transform GTK CSS to plain web CSS for the WebKit preview."""
    vars_ = collect_css_vars(css, style_path)

    # Strip @import and @define-color — all values are now in vars_
    css = _IMPORT_RE.sub("", css)
    css = _DEFINE_COLOR.sub("", css)

    # Resolve GTK alpha() function: alpha(@name, 0.72) → rgba(r, g, b, 0.72)
    def replace_alpha(m: re.Match) -> str:
        color = _resolve_color(m.group(1), vars_)
        return _color_to_rgba(color, float(m.group(2))) if color else m.group(0)
    css = _ALPHA_FN.sub(replace_alpha, css)

    # Replace bare @name color references with their resolved hex values
    def replace_ref(m: re.Match) -> str:
        resolved = _resolve_color(m.group(1), vars_)
        return resolved if resolved else m.group(0)
    css = _COLOR_REF.sub(replace_ref, css)

    # Map GTK-only selectors to HTML equivalents
    css = re.sub(r"window#waybar\s*>\s*box", "#waybar > .bar-inner", css)
    css = re.sub(r"window#waybar", "#waybar", css)

    # Strip GTK-only properties
    css = re.sub(r"-gtk-[^;]+;", "", css)
    css = re.sub(r"icon-size\s*:[^;]+;", "", css)
    return css


# ── HTML builder ──────────────────────────────────────────────────────────────

def _build_html(preset: Preset, preset_css: str) -> str:
    def mod_html(mod) -> str:
        if not mod.enabled:
            return ""
        css_id = mod.css_id
        if "." in css_id:
            id_part  = css_id.lstrip("#").split(".")[0]
            cls_part = " ".join(css_id.split(".")[1:])
            return f'<div id="{id_part}" class="module {cls_part}">{mod.display_name}</div>'
        return f'<div id="{css_id.lstrip("#")}" class="module">{mod.display_name}</div>'

    left   = "".join(mod_html(m) for m in preset.modules_left)
    center = "".join(mod_html(m) for m in preset.modules_center)
    right  = "".join(mod_html(m) for m in preset.modules_right)

    # IMPORTANT: preset_css goes in its own <style> tag — never nested inside another
    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
/* chrome — fixed, never overridden by preset CSS */
*, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
html, body {{
    width: 100%; height: 100%;
    overflow: hidden;
    background: transparent;
}}
body {{
    display: flex;
    flex-direction: column;
    align-items: stretch;
    justify-content: flex-start;
    position: relative;
}}
/* desktop background — sits behind the bar */
body::before {{
    content: "";
    position: fixed;
    inset: 0;
    background: linear-gradient(135deg, #0d1117 0%, #161b22 50%, #0d1117 100%);
    z-index: -1;
}}
/* fallback bar layout — preset rules override these */
#waybar {{
    position: relative;
    z-index: 1;
    display: flex;
    align-items: stretch;
    width: 100%;
    min-height: 32px;
}}
.bar-inner {{
    display: flex;
    align-items: center;
    width: 100%;
    min-height: 32px;
}}
.modules-left   {{ display: flex; align-items: center; flex: 1; gap: 2px; }}
.modules-center {{ display: flex; align-items: center; justify-content: center; gap: 2px; flex: 1; }}
.modules-right  {{ display: flex; align-items: center; justify-content: flex-end; gap: 2px; flex: 1; }}
.module {{ padding: 2px 6px; white-space: nowrap; }}
</style>
<style id="preset-css">
{preset_css}
</style>
</head>
<body>
<div id="waybar">
  <div class="bar-inner">
    <div class="modules-left">{left}</div>
    <div class="modules-center">{center}</div>
    <div class="modules-right">{right}</div>
  </div>
</div>
</body>
</html>"""


# ── Panel ─────────────────────────────────────────────────────────────────────

class PreviewPanel(Gtk.Box):

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._preset: Preset | None = None
        self._debounce: int = 0
        self._page_loaded = False
        self._webview = None
        self._build_ui()

    def _build_ui(self) -> None:
        header = Gtk.Label(label="Preview")
        header.add_css_class("heading")
        header.set_xalign(0)
        header.set_margin_start(12)
        header.set_margin_top(12)
        header.set_margin_bottom(6)
        self.append(header)

        if not _WEBKIT_OK:
            status = Gtk.Label(
                label="Install webkitgtk-6.0 for live preview:\nsudo pacman -S webkitgtk-6.0"
            )
            status.set_wrap(True)
            status.add_css_class("dim-label")
            status.set_margin_start(16)
            self.append(status)
            return

        self._webview = _WebKitLib.WebView()
        self._webview.set_vexpand(True)
        self._webview.set_hexpand(True)

        settings = self._webview.get_settings()
        settings.set_enable_javascript(True)
        if hasattr(settings, "set_enable_plugins"):
            settings.set_enable_plugins(False)

        # Track when the page finishes loading so JS injection is safe
        self._webview.connect("load-changed", self._on_load_changed)

        self.append(self._webview)

    def _on_load_changed(self, webview, load_event) -> None:
        LoadEvent = _WebKitLib.LoadEvent
        if load_event == LoadEvent.FINISHED:
            self._page_loaded = True

    def load_preset(self, preset: Preset) -> None:
        self._preset = preset
        self._page_loaded = False
        if self._webview is None:
            return
        css  = transform_css_for_browser(preset.css_raw, preset.style_path)
        html = _build_html(preset, css)
        self._webview.load_html(html, "file:///")

    def schedule_refresh(self) -> None:
        """Debounced CSS-only update — swaps the stylesheet without reloading."""
        if self._debounce:
            GLib.source_remove(self._debounce)
        self._debounce = GLib.timeout_add(250, self._do_refresh)

    def _do_refresh(self) -> bool:
        self._debounce = 0
        if self._webview is None or self._preset is None:
            return GLib.SOURCE_REMOVE

        if not self._page_loaded:
            # Page not ready yet — just do a full reload
            self.load_preset(self._preset)
            return GLib.SOURCE_REMOVE

        # Inject updated CSS via JS — no page reload, no flicker
        css = transform_css_for_browser(self._preset.css_raw, self._preset.style_path)
        # Escape backticks and backslashes for JS template literal
        css_escaped = css.replace("\\", "\\\\").replace("`", "\\`")
        js = f"""
(function() {{
    var el = document.getElementById('preset-css');
    if (el) {{ el.textContent = `{css_escaped}`; }}
}})();
"""
        self._webview.evaluate_javascript(js, -1, None, None, None, None, None)
        return GLib.SOURCE_REMOVE
