#!/usr/bin/env python3
"""
Cloud Center — GTK4/Libadwaita control panel for Hyprland.

Features (inspired by Dusky Control Center):
    - Standard window lifecycle: close exits app
  - Adw.NavigationSplitView: proper collapsible sidebar
  - Adw.ToastOverlay: action feedback
  - YAML-driven: add pages/items with zero Python
  - Search across all items
  - Structured logging
  - XDG-compliant pycache
  - Nerd Font icon support
    - Matugen auto-reload: watches colors file and reloads CSS
"""
from __future__ import annotations

import logging
import sys
import os
import json
import subprocess
from pathlib import Path

# ── XDG pycache before any local imports ─────────────────────────────────────
_CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "cloud-center"
_CACHE.mkdir(parents=True, exist_ok=True)
sys.pycache_prefix = str(_CACHE / "pycache")

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="[%(levelname)s] %(name)s: %(message)s",
    stream=sys.stderr,
)
log = logging.getLogger("cloud-center")

# ── Preflight (dep check before GTK) ─────────────────────────────────────────
import lib.utility as utility
utility.preflight_check()

# ── GTK imports ───────────────────────────────────────────────────────────────
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk

# --- SHELL STACK WIRING (Updated by installer) ---
ACTIVE_SHELL_TAB = "quickshell"

import lib.rows as rows
from lib.rows import RowContext
import lib.hcm_lua as hcm
import lib.keybind_manager_lua as keybind_manager
import lib.monitor_editor as monitor_editor
import lib.bluetooth_page as bluetooth_page
import lib.wifi_page as wifi_page
import lib.audio_page as audio_page
import lib.cursor_page as cursor_page
import lib.rules_startup_page as rules_startup_page
import lib.region_time_page as region_time_page
import lib.battery_page as battery_page

# ── YAML ──────────────────────────────────────────────────────────────────────
try:
    import yaml
except ImportError:
    sys.exit("[FATAL] python-yaml not installed. Run: sudo pacman -S python-yaml")

# ── Constants ─────────────────────────────────────────────────────────────────
APP_ID          = "dev.cloudyy.CloudCenter"
CONFIG_PATH     = SCRIPT_DIR / "config.yaml"
CSS_PATH        = SCRIPT_DIR / "assets" / "style.css"
MATUGEN_DIR     = Path.home() / ".config" / "matugen" / "generated"
MATUGEN_GTK_CSS = MATUGEN_DIR / "gtk-4.css"
MATUGEN_COLORS  = MATUGEN_DIR / "colors.css"
THEME_STATE     = Path.home() / ".config" / "hypr" / "theme_state" / "state.conf"
SEARCH_DEBOUNCE = 200   # ms
SIDEBAR_WIDTH   = 200   # px
# Above ~/.config/gtk-4.0/gtk.css (USER=800) so fresh matugen tokens win on hot reload.
CSS_PRIORITY    = Gtk.STYLE_PROVIDER_PRIORITY_USER + 1

CLI_PAGE_ALIASES: dict[str, str] = {
    "home": "home",
    "appearance": "appearance",
    "wallpapers": "wallpapers",
    "hyprland": "hyprland",
    "input": "input",
    "wifi": "__wifi__",
    "bluetooth": "__bt__",
    "monitors": "__mon__",
    "monitor": "__mon__",
    "audio": "__audio__",
    "config-manager": "__hcm__",
    "lua-config-manager": "__hcm__",
    "hcm": "__hcm__",
    "keybind-manager": "__hkbm__",
    "keybinds": "__hkbm__",
    "cursor": "__cursor__",
    "region": "__region__",
    "time": "__region__",
    "datetime": "__region__",
    "battery": "__battery__",
}


# ── Nerd Font icon helper ─────────────────────────────────────────────────────

def make_icon_widget(icon_name: str, css_classes: list[str] | None = None) -> Gtk.Widget:
    """
    Return a Gtk.Image for GTK symbolic icons, or a Gtk.Label for Nerd Font
    glyphs (any icon_name that contains a non-ASCII character).
    """
    css_classes = css_classes or []
    if not icon_name:
        placeholder = Gtk.Label(label="")
        return placeholder

    is_nerd = any(ord(c) > 127 for c in icon_name)

    if is_nerd:
        lbl = Gtk.Label(label=icon_name)
        lbl.add_css_class("nerd-icon")
        for cls in css_classes:
            lbl.add_css_class(cls)
        return lbl
    else:
        img = Gtk.Image.new_from_icon_name(icon_name)
        for cls in css_classes:
            img.add_css_class(cls)
        return img


# =============================================================================
# CONFIG LOADER
# =============================================================================

def load_config() -> dict:
    try:
        data = yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data
    except Exception as e:
        log.error("Failed to load config: %s", e)
    return {"pages": []}


def read_theme_mode() -> str:
    try:
        for line in THEME_STATE.read_text(encoding="utf-8").splitlines():
            if line.startswith("THEME_MODE="):
                val = line.split("=", 1)[1].strip().strip('"\'').lower()
                if val in {"light", "dark"}:
                    return val
    except (FileNotFoundError, OSError):
        pass
    return "dark"


def detect_touchpad() -> bool:
    """Best-effort touchpad detection across Hyprland/libinput/kernel sources."""
    # 1) Hyprland JSON devices (preferred when compositor is running).
    try:
        r = subprocess.run(
            ["hyprctl", "devices", "-j"],
            capture_output=True,
            text=True,
            timeout=2,
        )
        if r.returncode == 0 and r.stdout.strip():
            data = json.loads(r.stdout)
            for dev in data.get("mice", []):
                name = str(dev.get("name", "")).lower()
                if "touchpad" in name:
                    return True
    except Exception:
        pass

    # 2) libinput listing.
    try:
        r = subprocess.run(
            ["libinput", "list-devices"],
            capture_output=True,
            text=True,
            timeout=2,
        )
        if r.returncode == 0 and "touchpad" in r.stdout.lower():
            return True
    except Exception:
        pass

    # 3) Kernel input devices fallback.
    try:
        txt = Path("/proc/bus/input/devices").read_text(encoding="utf-8", errors="ignore")
        if "touchpad" in txt.lower():
            return True
    except Exception:
        pass

    return False


# =============================================================================
# MAIN WINDOW
# =============================================================================

class CloudCenterWindow(Adw.ApplicationWindow):

    def __init__(self, app: Adw.Application) -> None:
        super().__init__(application=app, title="Cloud Center")
        self.set_default_size(1200, 750)

        self._config   = load_config()
        self._toast_ov = Adw.ToastOverlay()
        self._ctx      = RowContext(self._toast_ov, self.navigate_to_page)
        self._has_touchpad = detect_touchpad()

        # All searchable items: (title, subtitle, widget_builder)
        self._search_index: list[dict] = []
        self._search_debounce: int = 0

        # Sidebar nav state
        self._nav_rows: dict[str, Gtk.ListBoxRow] = {}
        self._nav_list: Gtk.ListBox | None = None
        self._pinned_list: Gtk.ListBox | None = None
        self._nav_deselecting: bool = False

        # Heavy pages deferred until first navigation
        self._lazy_builders: dict = {}

        self._build_ui()
        self._setup_shortcuts()
        self._search_entry.grab_focus()
        log.info("Window ready")

    # ── UI construction ───────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        # Root: ToastOverlay → OverlaySplitView (proper show/hide sidebar support)
        self._split = Adw.OverlaySplitView()
        self._split.set_min_sidebar_width(SIDEBAR_WIDTH)
        self._split.set_max_sidebar_width(SIDEBAR_WIDTH)
        self._split.set_collapsed(False)
        self._split.set_pin_sidebar(True)

        # Sidebar and content are plain widgets (no NavigationPage wrappers needed)
        self._split.set_sidebar(self._build_sidebar())

        # Content stack
        self._stack = Adw.ViewStack()
        self._split.set_content(self._build_content_area())

        self._build_search_page()
        self._populate_pages()

        self._toast_ov.set_child(self._split)
        self.set_content(self._toast_ov)

    def _build_sidebar(self) -> Gtk.Widget:
        """Build sidebar navigation with category headers."""
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.add_css_class("sidebar-surface")

        # Header
        header = Adw.HeaderBar()
        header.set_show_end_title_buttons(False)
        header.add_css_class("flat")
        header.add_css_class("sidebar-surface")

        title_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        icon = make_icon_widget("", ["sidebar-app-icon"])
        lbl = Gtk.Label(label="Cloud Center")
        lbl.add_css_class("sidebar-app-title")
        title_box.append(icon)
        title_box.append(lbl)
        header.set_title_widget(title_box)
        box.append(header)

        # Search entry
        self._search_entry = Gtk.SearchEntry()
        self._search_entry.add_css_class("sidebar-surface")
        self._search_entry.set_placeholder_text("Search settings…")
        self._search_entry.set_margin_start(10)
        self._search_entry.set_margin_end(10)
        self._search_entry.set_margin_top(6)
        self._search_entry.set_margin_bottom(6)
        self._search_entry.connect("search-changed", self._on_search_changed)
        self._search_entry.connect("stop-search", self._on_search_stop)
        box.append(self._search_entry)

        # Categorized nav list
        scroll = Gtk.ScrolledWindow()
        scroll.add_css_class("sidebar-surface")
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)

        self._nav_list = Gtk.ListBox()
        self._nav_list.add_css_class("sidebar-surface")
        self._nav_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._nav_list.add_css_class("sidebar-nav-list")
        self._nav_list.connect("row-selected", self._on_nav_row_selected)

        yaml_pages = {
            p.get("id"): p for p in self._config.get("pages", []) if p.get("id")
        }
        builtins = {
            "__cursor__": {"id": "__cursor__", "title": "Cursor", "icon": "input-mouse-symbolic"},
            "__mon__": {"id": "__mon__", "title": "Monitors", "icon": "video-display-symbolic"},
            "__bt__": {"id": "__bt__", "title": "Bluetooth", "icon": "bluetooth-active-symbolic"},
            "__wifi__": {"id": "__wifi__", "title": "Wi-Fi", "icon": "network-wireless-signal-good-symbolic"},
            "__audio__": {"id": "__audio__", "title": "Audio", "icon": "audio-speakers-symbolic"},
            "__region__": {"id": "__region__", "title": "Region & Time", "icon": "mark-location-symbolic"},
            "__hkbm__": {"id": "__hkbm__", "title": "Keybind Manager", "icon": "input-keyboard-symbolic"},
            "__rules__": {"id": "__rules__", "title": "Rules & Startup", "icon": "preferences-system-symbolic"},
            "__battery__": {"id": "__battery__", "title": "Battery", "icon": "battery-good-symbolic"},
        }
        categories: list[tuple[str, list[str]]] = [
            ("Visuals",         ["appearance", "wallpapers", ACTIVE_SHELL_TAB, "hyprland", "terminal", "__rules__"]),
            ("Input & Display", ["input", "__cursor__", "__mon__", "__hkbm__"]),
            ("System",          ["__bt__", "__wifi__", "__audio__", "__region__", "__battery__"]),
        ]

        for title, ids in categories:
            self._nav_list.append(self._make_nav_category_row(title))
            for page_id in ids:
                page = yaml_pages.get(page_id) or builtins.get(page_id)
                if page:
                    self._nav_list.append(self._make_nav_row(page))

        scroll.set_child(self._nav_list)
        box.append(scroll)

        # Pinned bottom: System Overview (home page) — only if home page exists
        home_page = yaml_pages.get("home")
        if home_page:
            sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
            box.append(sep)

            self._pinned_list = Gtk.ListBox()
            self._pinned_list.add_css_class("sidebar-surface")
            self._pinned_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
            self._pinned_list.add_css_class("sidebar-nav-list")
            self._pinned_list.connect("row-selected", self._on_nav_row_selected)

            home_display = dict(home_page)
            home_display["title"] = "System Overview"
            home_row = self._make_nav_row(home_display)
            # Re-register under "home" key so navigate_to_page("home") still works
            self._nav_rows["home"] = home_row
            self._pinned_list.append(home_row)

            box.append(self._pinned_list)

        return box

    def _make_nav_category_row(self, title: str) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row.set_selectable(False)
        row.set_activatable(False)
        row.add_css_class("sidebar-category-row")

        label = Gtk.Label(label=title)
        label.set_xalign(0)
        label.add_css_class("sidebar-category-label")
        label.set_margin_start(12)
        label.set_margin_end(12)
        label.set_margin_top(12)
        label.set_margin_bottom(4)
        row.set_child(label)
        return row

    def _make_nav_row(self, page: dict) -> Gtk.ListBoxRow:
        """Create a single navigation row."""
        page_id = page.get("id")
        title = page.get("title", page_id)
        icon = page.get("icon", "")

        row = Gtk.ListBoxRow()
        row._page_id = page_id  # type: ignore[attr-defined]
        row.set_selectable(True)
        row.add_css_class("sidebar-nav-row")

        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        hbox.set_margin_start(12)
        hbox.set_margin_end(12)
        hbox.set_margin_top(8)
        hbox.set_margin_bottom(8)

        if icon:
            hbox.append(make_icon_widget(icon))

        title_label = Gtk.Label(label=title)
        title_label.set_xalign(0)
        title_label.set_hexpand(True)
        hbox.append(title_label)

        row.set_child(hbox)
        self._nav_rows[page_id] = row
        return row

    def _build_content_area(self) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

        # Content header bar
        self._content_header = Adw.HeaderBar()
        self._content_header.add_css_class("flat")

        # Sidebar fold/unfold toggle
        self._sidebar_btn = Gtk.ToggleButton()
        self._sidebar_btn.set_icon_name("sidebar-show-symbolic")
        self._sidebar_btn.add_css_class("flat")
        self._sidebar_btn.set_active(True)
        self._sidebar_btn.set_tooltip_text("Toggle sidebar")
        self._sidebar_btn.connect("toggled", self._on_sidebar_toggle)
        self._content_header.pack_start(self._sidebar_btn)

        box.append(self._content_header)

        # Stack
        self._stack = Adw.ViewStack()
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)
        scroll.set_child(self._stack)
        box.append(scroll)

        return box

    def _build_search_page(self) -> None:
        """Build the search results page (empty until user types)."""
        self._search_group = Adw.PreferencesGroup()
        self._search_group.set_title("Search Results")
        self._search_rows: list[Gtk.Widget] = []

        page_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        page_box.set_margin_start(16)
        page_box.set_margin_end(16)
        page_box.set_margin_top(16)
        page_box.set_margin_bottom(16)
        page_box.append(self._search_group)

        clamp = Adw.Clamp()
        clamp.set_child(page_box)
        self._stack.add_named(clamp, "__search__")

    def _populate_pages(self, select_first: bool = True) -> None:
        """Build stack pages for each YAML page + hardcoded managers."""
        pages = self._config.get("pages", [])
        if not pages:
            self._show_empty()
            return

        # Build content pages for YAML pages
        for page_cfg in pages:
            pid = page_cfg.get("id", page_cfg.get("title", "").lower())
            content = self._build_page_content(page_cfg)
            self._stack.add_named(content, pid)

        # Register heavy pages as lazy builders — built on first navigation
        self._lazy_builders = {
            "__cursor__": lambda: cursor_page.CursorPage(self._toast_ov),
            "__bt__":    lambda: bluetooth_page.BluetoothPage(self._toast_ov),
            "__wifi__":  lambda: wifi_page.WiFiPage(self._toast_ov),
            "__mon__":   lambda: monitor_editor.MonitorEditorPage(self._toast_ov),
            "__hkbm__":  lambda: keybind_manager.LuaKeybindManagerPage(self._toast_ov),
            "__rules__": lambda: rules_startup_page.RulesStartupPage(self._toast_ov),
            "__audio__": lambda: audio_page.AudioPage(self._toast_ov),
            "__region__": lambda: region_time_page.RegionTimePage(self._toast_ov),
            "__battery__": lambda: battery_page.BatteryPage(self._toast_ov),
        }

        if select_first and pages:
            first_pid = pages[0].get("id", pages[0].get("title", "").lower())
            row = self._nav_rows.get(first_pid)
            if row:
                parent = row.get_parent()
                if isinstance(parent, Gtk.ListBox):
                    parent.select_row(row)
            self._stack.set_visible_child_name(first_pid)

    def _build_page_content(self, page_cfg: dict) -> Gtk.Widget:
        """Build an Adw.PreferencesPage from YAML layout."""
        pref_page = Adw.PreferencesPage()
        page_id = page_cfg.get("id", "")
        pref_page.set_title(page_cfg.get("title", ""))

        for section_cfg in page_cfg.get("layout", []):
            group = self._build_section(section_cfg, page_id)
            if group:
                pref_page.add(group)

        return pref_page

    def _build_section(self, section_cfg: dict, page_id: str = "") -> Adw.PreferencesGroup | None:
        props = section_cfg.get("properties", {})

        # Hide touchpad controls when no touchpad is present.
        if props.get("requires_touchpad", False) and not self._has_touchpad:
            return None
        if page_id == "input" and str(props.get("title", "")).strip().lower() == "touchpad" and not self._has_touchpad:
            return None

        group = Adw.PreferencesGroup()

        if title := props.get("title"):
            group.set_title(title)
        if desc := props.get("description"):
            group.set_description(desc)

        for item in section_cfg.get("items", []):
            widget = rows.build_row(item, self._ctx)
            if widget:
                group.add(widget)
                # Index for search
                p = item.get("properties", {})
                self._search_index.append({
                    "title":    p.get("title", ""),
                    "subtitle": p.get("description", ""),
                    "item":     item,
                })

        return group

    def _show_empty(self) -> None:
        status = Adw.StatusPage(
            icon_name="document-open-symbolic",
            title="No Configuration",
            description=f"Add pages to {CONFIG_PATH.name} to get started.",
        )
        self._stack.add_named(status, "__empty__")
        self._stack.set_visible_child_name("__empty__")

    def _show_error(self, msg: str) -> None:
        status = Adw.StatusPage(
            icon_name="dialog-error-symbolic",
            title="Configuration Error",
            description=msg,
        )
        hint = Gtk.Label(label="Fix config.yaml and press Ctrl+R to reload.")
        hint.add_css_class("dim-label")
        hint.set_margin_top(12)
        status.set_child(hint)
        self._stack.add_named(status, "__error__")
        self._stack.set_visible_child_name("__error__")

    # ── Navigation ────────────────────────────────────────────────────────────

    def _on_nav_selected(self, row: Gtk.ListBoxRow, page_id: str) -> None:
        """Handle sidebar page selection."""
        if row is None:
            return
        # Clear search
        self._search_entry.set_text("")
        # Build deferred page on first navigation
        if page_id in self._lazy_builders:
            page = self._lazy_builders.pop(page_id)()
            page.set_vexpand(True)
            self._stack.add_named(page, page_id)
        if page_id and self._stack.get_child_by_name(page_id):
            self._stack.set_visible_child_name(page_id)
            row_child = row.get_child()
            if row_child and isinstance(row_child, Gtk.Box):
                children = []
                child = row_child.get_first_child()
                while child:
                    children.append(child)
                    child = child.get_next_sibling()
                if children:
                    self._content_header.set_title_widget(Gtk.Label(label=""))

    def navigate_to_page(self, page_id: str) -> bool:
        """Navigate to a page id and keep sidebar selection in sync."""
        if not page_id:
            return False
        # Build deferred page on demand (e.g. from CLI --page flag)
        if page_id in self._lazy_builders:
            page = self._lazy_builders.pop(page_id)()
            page.set_vexpand(True)
            self._stack.add_named(page, page_id)
        if self._stack.get_child_by_name(page_id) is None:
            return False
        self._search_entry.set_text("")
        self._stack.set_visible_child_name(page_id)
        row = self._nav_rows.get(page_id)
        if row:
            parent = row.get_parent()
            if isinstance(parent, Gtk.ListBox):
                parent.select_row(row)
                if parent is self._nav_list and self._pinned_list is not None:
                    self._pinned_list.unselect_all()
                elif parent is self._pinned_list and self._nav_list is not None:
                    self._nav_list.unselect_all()
        return True
    
    def _on_nav_row_selected(self, listbox: Gtk.ListBox, row: Gtk.ListBoxRow | None) -> None:
        """Handle row selection in the sidebar nav list."""
        if row is None or self._nav_deselecting:
            return
        self._nav_deselecting = True
        try:
            if listbox is self._nav_list and self._pinned_list is not None:
                self._pinned_list.unselect_all()
            elif listbox is self._pinned_list and self._nav_list is not None:
                self._nav_list.unselect_all()
        finally:
            self._nav_deselecting = False
        page_id = getattr(row, "_page_id", None)
        if page_id:
            self._on_nav_selected(row, page_id)

    def _on_sidebar_toggle(self, btn: Gtk.ToggleButton) -> None:
        """Fold or unfold the sidebar panel."""
        self._split.set_show_sidebar(btn.get_active())

    # ── Search ────────────────────────────────────────────────────────────────

    def _on_search_changed(self, entry: Gtk.SearchEntry) -> None:
        if self._search_debounce:
            GLib.source_remove(self._search_debounce)
        self._search_debounce = GLib.timeout_add(
            SEARCH_DEBOUNCE, self._do_search, entry.get_text().strip()
        )

    def _on_search_stop(self, entry: Gtk.SearchEntry) -> None:
        self._search_entry.set_text("")
        if self._nav_rows:
            first_row = next(iter(self._nav_rows.values()))
            page_id = getattr(first_row, "_page_id", None)
            if page_id:
                self.navigate_to_page(page_id)

    def _do_search(self, query: str) -> bool:
        self._search_debounce = 0
        if not query:
            return GLib.SOURCE_REMOVE

        self._stack.set_visible_child_name("__search__")
        self._content_header.set_title_widget(
            Gtk.Label(label=f'Results for "{query}"')
        )

        # Clear previous results (only rows we actually added).
        for row in self._search_rows:
            try:
                self._search_group.remove(row)
            except Exception:
                pass
        self._search_rows.clear()

        ql = query.lower()
        matched = 0
        for entry in self._search_index:
            if ql in entry["title"].lower() or ql in entry["subtitle"].lower():
                widget = rows.build_row(entry["item"], self._ctx)
                if widget:
                    self._search_group.add(widget)
                    self._search_rows.append(widget)
                    matched += 1
                if matched >= 50:
                    break

        if matched == 0:
            placeholder = Adw.ActionRow(
                title="No results",
                subtitle=f"Nothing matched '{query}'",
            )
            placeholder.add_css_class("dim-label")
            self._search_group.add(placeholder)
            self._search_rows.append(placeholder)

        return GLib.SOURCE_REMOVE

    # ── Keyboard shortcuts ────────────────────────────────────────────────────

    def _setup_shortcuts(self) -> None:
        ctrl = Gtk.EventControllerKey()
        ctrl.connect("key-pressed", self._on_key)
        self.add_controller(ctrl)

    def _on_key(self, ctrl, keyval, keycode, state) -> bool:
        mods = state & Gdk.ModifierType.CONTROL_MASK
        alt_mods = state & Gdk.ModifierType.ALT_MASK
        
        # ── Global Shortcuts ──────────────────────────────────────────────────
        
        # Ctrl+Q: Quit
        if mods and keyval == Gdk.KEY_q:
            self.close()
            return True
            
        # Ctrl+R: Reload
        if mods and keyval == Gdk.KEY_r:
            self._reload()
            return True

        # Ctrl+F or '/': Focus search
        if (mods and keyval == Gdk.KEY_f) or (not mods and keyval == Gdk.KEY_slash):
            self._search_entry.grab_focus()
            return True

        # Ctrl+H: Go Home
        if mods and keyval == Gdk.KEY_h:
            self.navigate_to_page("home")
            return True

        # Ctrl+Tab: Cycle focus between sidebar and search/content
        if mods and keyval == Gdk.KEY_Tab:
            focus = self.get_focus()
            if focus and (focus is self._nav_list or focus is self._pinned_list or focus.get_ancestor(Gtk.ListBox) in (self._nav_list, self._pinned_list)):
                self._search_entry.grab_focus()
            else:
                if self._nav_list:
                    self._nav_list.grab_focus()
            return True

        # Alt+1-9: Jump to pages
        if alt_mods and Gdk.KEY_1 <= keyval <= Gdk.KEY_9:
            index = keyval - Gdk.KEY_1
            page_ids = list(self._nav_rows.keys())
            if index < len(page_ids):
                self.navigate_to_page(page_ids[index])
                return True

        # ── Contextual Handling ───────────────────────────────────────────────

        if keyval == Gdk.KEY_Escape:
            self._on_search_stop(self._search_entry)
            # Clear focus from whatever was focused
            self.set_focus(None)
            return True

        focus = self.get_focus()
        
        # Search entry specific navigation
        if focus is self._search_entry:
            # Down arrow from search entry: focus first result
            if keyval == Gdk.KEY_Down:
                if self._search_rows:
                    self._search_rows[0].grab_focus()
                    return True

        if focus is not None:
            # Do not hijack typing when the user is editing text in a row widget.
            if isinstance(focus, (Gtk.Entry, Gtk.SearchEntry, Gtk.SpinButton, Gtk.TextView)):
                return False
            editable = getattr(Gtk, "Editable", None)
            if editable is not None and isinstance(focus, editable):
                return False

        # Focus search on any printable key (Type-to-search)
        if not mods and not alt_mods and keyval not in (Gdk.KEY_Tab, Gdk.KEY_Return, Gdk.KEY_ISO_Left_Tab):
            # Check if it's a printable character
            if Gdk.keyval_to_unicode(keyval) != 0:
                self._search_entry.grab_focus()
                # We don't return True here so the key event propagates to the entry
        
        return False

    def _rebuild_pages(self, restore_page: str | None = None) -> None:
        """Rebuild stack pages so freshly loaded CSS tokens are applied."""
        while page := self._stack.get_first_child():
            self._stack.remove(page)

        self._search_index.clear()
        self._build_search_page()
        skip_first = bool(restore_page and restore_page != "__search__")
        self._populate_pages(select_first=not skip_first)

        if restore_page and restore_page != "__search__":
            self.navigate_to_page(restore_page)

    def _reload(self, show_toast: bool = True) -> None:
        log.info("Reloading config…")

        visible_name = self._stack.get_visible_child_name()
        self._config = load_config()
        self._rebuild_pages(visible_name)

        if show_toast:
            utility.toast(self._toast_ov, "Config reloaded")
        log.info("Reload complete")

    def refresh_theme_ui(self) -> None:
        """Recompute styles after CSS reload (no page rebuild needed)."""
        display = Gdk.Display.get_default()
        if display and hasattr(Gtk.StyleContext, "reset_widgets"):
            Gtk.StyleContext.reset_widgets(display)
        self.queue_draw()


# =============================================================================
# APPLICATION
# =============================================================================

class CloudCenter(Adw.Application):

    def __init__(self) -> None:
        super().__init__(
            application_id=APP_ID,
            flags=Gio.ApplicationFlags.DEFAULT_FLAGS,
        )
        self._window: CloudCenterWindow | None = None
        self._matugen_monitors: list[Gio.FileMonitor] = []
        self._matugen_debounce: int = 0
        self._app_provider: Gtk.CssProvider | None = None
        self._requested_page: str | None = None
        self._register_cli_options()

    def _register_cli_options(self) -> None:
        self.add_main_option(
            "page", ord("p"), GLib.OptionFlags.NONE, GLib.OptionArg.STRING,
            "Open a specific Cloud Center page", "PAGE",
        )
        flag_specs = [
            ("home", "Open Home page"),
            ("appearance", "Open Appearance page"),
            ("wallpapers", "Open Wallpapers page"),
            ("hyprland", "Open Hyprland page"),
            ("input", "Open Input page"),
            ("wifi", "Open Wi-Fi page"),
            ("bluetooth", "Open Bluetooth page"),
            ("monitors", "Open Monitors page"),
            ("audio", "Open Audio page"),
            ("config-manager", "Open Lua Config Manager page"),
            ("lua-config-manager", "Open Lua Config Manager page"),
            ("keybind-manager", "Open Keybind Manager page"),
            ("keybinds", "Open Keybind Manager page"),
            ("region", "Open Region & Time page"),
            ("time", "Open Region & Time page"),
            ("datetime", "Open Region & Time page"),
        ]
        for opt, desc in flag_specs:
            self.add_main_option(
                opt,
                0,
                GLib.OptionFlags.NONE,
                GLib.OptionArg.NONE,
                desc,
                None,
            )

    def do_handle_local_options(self, options: GLib.VariantDict) -> int:
        page_variant = options.lookup_value("page", GLib.VariantType.new("s"))
        if page_variant is not None:
            requested = page_variant.get_string().strip().lower()
            self._requested_page = CLI_PAGE_ALIASES.get(requested, requested)

        for flag in (
            "home", "appearance", "wallpapers", "hyprland", "input",
            "wifi", "bluetooth", "monitors", "audio",
            "config-manager", "lua-config-manager",
            "keybind-manager", "keybinds",
            "region", "time", "datetime",
        ):
            if options.contains(flag):
                self._requested_page = CLI_PAGE_ALIASES.get(flag, flag)

        # Continue normal activation.
        return -1

    def do_activate(self) -> None:
        if self._window is None:
            self._window = CloudCenterWindow(self)
            self._window.connect("close-request", self._on_close)
            self._window.connect("destroy", self._on_destroy)
            self._apply_theme_mode()
            self._load_css()
            self._start_matugen_watcher()
        if self._requested_page and not self._window.navigate_to_page(self._requested_page):
            log.warning("Unknown page target requested: %s", self._requested_page)
        self._window.present()

    def _apply_theme_mode(self) -> None:
        mode = read_theme_mode()
        manager = Adw.StyleManager.get_default()
        manager.set_color_scheme(
            Adw.ColorScheme.FORCE_LIGHT if mode == "light" else Adw.ColorScheme.FORCE_DARK
        )
        log.info("Applied Adw color scheme: %s", mode)

    def _on_close(self, win: CloudCenterWindow) -> bool:
        """Allow normal close (destroy window and quit app)."""
        return False

    def _on_destroy(self, _win: CloudCenterWindow) -> None:
        self._window = None

    def _start_matugen_watcher(self) -> None:
        """Watch matugen generated directory/files and hot-reload app theme."""
        for mon in self._matugen_monitors:
            try:
                mon.cancel()
            except Exception:
                pass
        self._matugen_monitors.clear()

        if not MATUGEN_DIR.exists():
            log.info("Matugen generated dir not found, skipping watcher: %s", MATUGEN_DIR)
            return

        targets = [MATUGEN_DIR, MATUGEN_GTK_CSS, MATUGEN_COLORS]
        for target in targets:
            if not target.exists():
                continue
            gfile = Gio.File.new_for_path(str(target))
            if target.is_dir():
                mon = gfile.monitor_directory(Gio.FileMonitorFlags.NONE, None)
            else:
                mon = gfile.monitor_file(Gio.FileMonitorFlags.NONE, None)
            mon.connect("changed", self._on_matugen_changed)
            self._matugen_monitors.append(mon)

        log.info("Watching matugen theme outputs in: %s", MATUGEN_DIR)

    def _on_matugen_changed(
        self, monitor: Gio.FileMonitor, file: Gio.File,
        other_file: Gio.File, event_type: Gio.FileMonitorEvent
    ) -> None:
        if event_type not in (
            Gio.FileMonitorEvent.CHANGED,
            Gio.FileMonitorEvent.CREATED,
            Gio.FileMonitorEvent.CHANGES_DONE_HINT,
            Gio.FileMonitorEvent.MOVED_IN,
        ):
            return
        log.info("Matugen colors updated — scheduling reload")
        if self._matugen_debounce:
            GLib.source_remove(self._matugen_debounce)
        self._matugen_debounce = GLib.timeout_add(600, self._do_matugen_reload)

    def _do_matugen_reload(self) -> bool:
        """Reload CSS after matugen regenerates colors."""
        self._matugen_debounce = 0
        self._apply_theme_mode()
        ok = self._load_css()
        if self._window is not None:
            self._window.refresh_theme_ui()
        if self._window:
            utility.toast(self._window._toast_ov, "Theme updated" if ok else "Theme reload failed")
        return GLib.SOURCE_REMOVE

    def _load_css(self) -> bool:
        display = Gdk.Display.get_default()
        if display is None:
            return False

        if self._app_provider is not None:
            Gtk.StyleContext.remove_provider_for_display(display, self._app_provider)

        self._app_provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(
            display,
            self._app_provider,
            CSS_PRIORITY,
        )

        try:
            loaded_matugen = False
            gtk_exists = MATUGEN_GTK_CSS.exists()
            colors_exists = MATUGEN_COLORS.exists()

            # gtk-4.css has the GTK @define-color names style.css expects.
            if gtk_exists:
                matugen_text = MATUGEN_GTK_CSS.read_text(encoding="utf-8")
                loaded_matugen = True
                log.info("Loaded matugen GTK css: %s", MATUGEN_GTK_CSS)
            elif colors_exists:
                matugen_text = MATUGEN_COLORS.read_text(encoding="utf-8")
                loaded_matugen = True
                log.info("Loaded matugen colors css: %s", MATUGEN_COLORS)
                alias_text = """
@define-color window_bg_color @background;
@define-color window_fg_color @on_background;
@define-color view_bg_color @surface;
@define-color view_fg_color @on_surface;
@define-color card_bg_color @surface_container;
@define-color card_fg_color @on_surface;
@define-color headerbar_bg_color @surface;
@define-color headerbar_fg_color @on_surface;
@define-color popover_bg_color @surface_container;
@define-color popover_fg_color @on_surface;
@define-color accent_color @primary;
@define-color accent_bg_color @primary;
@define-color accent_fg_color @on_primary;
@define-color sidebar_bg_color @surface;
@define-color sidebar_fg_color @on_surface;
"""
                matugen_text = f"{matugen_text}\n{alias_text}\n"
            else:
                log.warning("No matugen CSS file found under %s", MATUGEN_DIR)
                matugen_text = ""

            if CSS_PATH.exists():
                app_text = CSS_PATH.read_text(encoding="utf-8")
            else:
                log.warning("App css not found: %s", CSS_PATH)
                app_text = ""

            merged_css = f"{matugen_text}\n{app_text}\n"
            self._app_provider.load_from_data(merged_css.encode("utf-8"))

            if hasattr(Gtk.StyleContext, "reset_widgets"):
                Gtk.StyleContext.reset_widgets(display)
            return loaded_matugen
        except Exception as e:
            log.error("CSS load failed: %s", e)
            return False


# =============================================================================
# ENTRY POINT
# =============================================================================

def main() -> int:
    return CloudCenter().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
