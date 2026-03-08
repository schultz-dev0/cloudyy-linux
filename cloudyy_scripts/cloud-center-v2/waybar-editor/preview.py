"""
waybar-editor/panels/preview.py
Right panel: WebKitGTK6 live preview of the waybar style.

Transforms GTK CSS syntax into browser-compatible CSS:
  @define-color name value  →  :root { --name: value; }
  @name                     →  var(--name)
"""
from __future__ import annotations

import re
from typing import Optional

from gi.repository import GLib, Gtk

from models import Preset

# Try WebKit 6.0 (GTK4-native), fall back to 4.1
_WEBKIT_OK = False
try:
    import gi
    gi.require_version("WebKit", "6.0")
    from gi.repository import WebKit as WebKitLib
    _WEBKIT_OK = True
except Exception:
    try:
        gi.require_version("WebKit2", "4.1")
        from gi.repository import WebKit2 as WebKitLib
        _WEBKIT_OK = True
    except Exception:
        WebKitLib = None


# ── CSS transformer ───────────────────────────────────────────────────────────

_DEFINE_COLOR = re.compile(r"@define-color\s+(\w+)\s+(.+?)\s*;")
_COLOR_REF    = re.compile(r"@([\w]+)")

def transform_css_for_browser(css: str) -> str:
    """Convert GTK CSS to browser-compatible CSS."""
    # Collect all @define-color declarations
    vars_: dict[str, str] = {}
    for m in _DEFINE_COLOR.finditer(css):
        vars_[m.group(1)] = m.group(2).strip()

    # Remove @define-color lines
    css = _DEFINE_COLOR.sub("", css)

    # Replace @name references with var(--name)
    def replace_ref(m):
        name = m.group(1)
        return f"var(--{name})" if name in vars_ else m.group(0)
    css = _COLOR_REF.sub(replace_ref, css)

    # Build :root block with CSS custom properties
    if vars_:
        root_vars = "\n".join(f"  --{k}: {v};" for k, v in vars_.items())
        css = f":root {{\n{root_vars}\n}}\n\n" + css

    # Strip GTK-specific properties browsers don't understand
    css = re.sub(r"-gtk-[^;]+;", "", css)
    css = re.sub(r"icon-size\s*:[^;]+;", "", css)

    return css


# ── Preview HTML template ─────────────────────────────────────────────────────

def _build_html(preset: Preset, css: str) -> str:
    """
    Build an HTML page that mirrors the waybar structure using its real CSS.
    Module names become divs with the matching CSS id/class selectors.
    """

    def module_html(mod) -> str:
        # Derive HTML id from css_id: "#clock" → id="clock"
        css_id = mod.css_id
        if "." in css_id:
            # e.g. #pulseaudio.output → id="pulseaudio" class="output"
            id_part  = css_id.lstrip("#").split(".")[0]
            cls_part = " ".join(css_id.split(".")[1:])
            tag = f'<div id="{id_part}" class="module {cls_part}">{mod.display_name}</div>'
        else:
            id_part = css_id.lstrip("#")
            tag = f'<div id="{id_part}" class="module">{mod.display_name}</div>'
        return tag if mod.enabled else f'<!-- {mod.name} disabled -->'

    left_html   = "\n".join(module_html(m) for m in preset.modules_left)
    center_html = "\n".join(module_html(m) for m in preset.modules_center)
    right_html  = "\n".join(module_html(m) for m in preset.modules_right)

    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
/* ── Reset ── */
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{
    background: #111;
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
    padding: 24px;
}}

/* ── Preview chrome ── */
.preview-wrap {{
    width: 100%;
}}
.preview-label {{
    color: #888;
    font-size: 11px;
    text-align: center;
    margin-bottom: 8px;
    font-family: monospace;
    letter-spacing: 0.05em;
}}

/* ── Bar layout ── */
#waybar {{
    display: flex;
    align-items: center;
    width: 100%;
    min-height: 36px;
    overflow: hidden;
}}
.modules-left   {{ display: flex; align-items: center; flex: 1; gap: 4px; }}
.modules-center {{ display: flex; align-items: center; justify-content: center; gap: 4px; }}
.modules-right  {{ display: flex; align-items: center; justify-content: flex-end; flex: 1; gap: 4px; }}

/* ── Module defaults ── */
.module {{
    padding: 2px 8px;
    white-space: nowrap;
}}

/* ── Injected preset CSS ── */
<style id="dynamic">
{css}
</style>
</style>
</head>
<body>
<div class="preview-wrap">
  <div class="preview-label">↓  live preview  ↓</div>
  <div id="waybar" class="bar">
    <div class="modules-left">{left_html}</div>
    <div class="modules-center">{center_html}</div>
    <div class="modules-right">{right_html}</div>
  </div>
</div>
</body>
</html>"""


# ── Panel ─────────────────────────────────────────────────────────────────────

class PreviewPanel(Gtk.Box):

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._preset: Optional[Preset] = None
        self._debounce: int = 0
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
            status = Adw.StatusPage(
                icon_name="dialog-warning-symbolic",
                title="WebKit not available",
                description=(
                    "Install webkit2gtk-6.0 (or webkit2gtk-4.1) for live preview.\n\n"
                    "sudo pacman -S webkitgtk-6.0"
                ),
            )
            self.append(status)
            return

        self._webview = WebKitLib.WebView()
        self._webview.set_vexpand(True)
        self._webview.set_hexpand(True)

        # Security: no network, no plugins
        settings = self._webview.get_settings()
        settings.set_enable_javascript(True)
        settings.set_enable_plugins(False)

        self.append(self._webview)

    def load_preset(self, preset: Preset) -> None:
        self._preset = preset
        self._refresh_now()

    def schedule_refresh(self) -> None:
        """Debounce rapid updates (e.g. slider dragging)."""
        if self._debounce:
            GLib.source_remove(self._debounce)
        self._debounce = GLib.timeout_add(300, self._do_refresh)

    def _do_refresh(self) -> bool:
        self._debounce = 0
        self._refresh_now()
        return GLib.SOURCE_REMOVE

    def _refresh_now(self) -> None:
        if self._webview is None or self._preset is None:
            return
        css  = transform_css_for_browser(self._preset.css_raw)
        html = _build_html(self._preset, css)
        self._webview.load_html(html, "file:///")
