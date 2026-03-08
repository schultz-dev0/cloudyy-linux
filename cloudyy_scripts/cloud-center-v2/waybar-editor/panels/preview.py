"""
waybar-editor/panels/preview.py
Right panel: WebKitGTK live preview of the waybar style.
"""
from __future__ import annotations

import re
from typing import Optional

from gi.repository import GLib, Gtk

from models import Preset

_WEBKIT_OK = False
_WebKitLib = None
try:
    import gi
    gi.require_version("WebKit", "6.0")
    from gi.repository import WebKit as _WebKitLib
    _WEBKIT_OK = True
except Exception:
    try:
        import gi
        gi.require_version("WebKit2", "4.1")
        from gi.repository import WebKit2 as _WebKitLib
        _WEBKIT_OK = True
    except Exception:
        pass


# ── CSS transformer ───────────────────────────────────────────────────────────

_DEFINE_COLOR = re.compile(r"@define-color\s+(\w+)\s+(.+?)\s*;")
_COLOR_REF    = re.compile(r"@([\w]+)")


def transform_css_for_browser(css: str) -> str:
    vars_: dict[str, str] = {}
    for m in _DEFINE_COLOR.finditer(css):
        vars_[m.group(1)] = m.group(2).strip()

    css = _DEFINE_COLOR.sub("", css)

    def replace_ref(m):
        name = m.group(1)
        return f"var(--{name})" if name in vars_ else m.group(0)
    css = _COLOR_REF.sub(replace_ref, css)

    if vars_:
        root_vars = "\n".join(f"  --{k}: {v};" for k, v in vars_.items())
        css = f":root {{\n{root_vars}\n}}\n\n" + css

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
/* chrome — fixed, never overridden */
*, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
html, body {{
    width: 100%; height: 100%;
    background: #111;
    overflow: hidden;
}}
body {{
    display: flex;
    flex-direction: column;
    align-items: stretch;
    justify-content: flex-start;
}}
/* fallback bar layout so it shows even if preset has no layout rules */
#waybar {{
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
  <div class="modules-left">{left}</div>
  <div class="modules-center">{center}</div>
  <div class="modules-right">{right}</div>
</div>
</body>
</html>"""


# ── Panel ─────────────────────────────────────────────────────────────────────

class PreviewPanel(Gtk.Box):

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._preset: Optional[Preset] = None
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
        css  = transform_css_for_browser(preset.css_raw)
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
        css = transform_css_for_browser(self._preset.css_raw)
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
