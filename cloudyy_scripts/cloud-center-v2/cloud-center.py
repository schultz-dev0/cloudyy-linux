#!/usr/bin/env python3
"""
Cloud Center — GTK4/Libadwaita control panel for Hyprland.

Features (inspired by Dusky Control Center):
  - Daemon mode: hides on close, instant relaunch via single-instance
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

import lib.rows as rows
from lib.rows import RowContext
import lib.hcm as hcm

# ── YAML ──────────────────────────────────────────────────────────────────────
try:
    import yaml
except ImportError:
    sys.exit("[FATAL] python-yaml not installed. Run: sudo pacman -S python-yaml")

# ── Constants ─────────────────────────────────────────────────────────────────
APP_ID          = "dev.cloudyy.CloudCenter"
CONFIG_PATH     = SCRIPT_DIR / "config.yaml"
CSS_PATH        = SCRIPT_DIR / "assets" / "style.css"
MATUGEN_COLORS  = Path.home() / ".config" / "matugen" / "generated" / "waybar-colors.css"
SEARCH_DEBOUNCE = 200   # ms
SIDEBAR_WIDTH   = 200   # px


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


# =============================================================================
# MAIN WINDOW
# =============================================================================

class CloudCenterWindow(Adw.ApplicationWindow):

    def __init__(self, app: Adw.Application) -> None:
        super().__init__(application=app, title="Cloud Center")
        self.set_default_size(1200, 750)

        self._config   = load_config()
        self._toast_ov = Adw.ToastOverlay()
        self._ctx      = RowContext(self._toast_ov)

        # All searchable items: (title, subtitle, widget_builder)
        self._search_index: list[dict] = []
        self._search_debounce: int = 0

        self._build_ui()
        self._setup_shortcuts()
        log.info("Window ready")

    # ── UI construction ───────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        # Root: ToastOverlay → NavigationSplitView
        split = Adw.NavigationSplitView()
        split.set_min_sidebar_width(SIDEBAR_WIDTH)
        split.set_max_sidebar_width(SIDEBAR_WIDTH)

        # Sidebar
        sidebar_nav = Adw.NavigationPage(title="Cloud Center")
        sidebar_nav.set_child(self._build_sidebar())
        split.set_sidebar(sidebar_nav)

        # Content stack wrapped in NavigationPage
        self._stack = Adw.ViewStack()
        self._content_nav = Adw.NavigationPage(title="Content")
        self._content_nav.set_child(self._build_content_area())
        split.set_content(self._content_nav)

        self._build_search_page()
        self._populate_pages()

        self._toast_ov.set_child(split)
        self.set_content(self._toast_ov)

    def _build_sidebar(self) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

        # Header
        header = Adw.HeaderBar()
        header.set_show_end_title_buttons(False)
        header.add_css_class("flat")

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
        self._search_entry.set_placeholder_text("Search settings…")
        self._search_entry.set_margin_start(10)
        self._search_entry.set_margin_end(10)
        self._search_entry.set_margin_top(6)
        self._search_entry.set_margin_bottom(6)
        self._search_entry.connect("search-changed", self._on_search_changed)
        self._search_entry.connect("stop-search", self._on_search_stop)
        box.append(self._search_entry)

        # Nav list
        self._nav_list = Gtk.ListBox()
        self._nav_list.add_css_class("navigation-sidebar")
        self._nav_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._nav_list.connect("row-selected", self._on_nav_selected)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)
        scroll.set_child(self._nav_list)
        box.append(scroll)

        return box

    def _build_content_area(self) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

        # Content header bar
        self._content_header = Adw.HeaderBar()
        self._content_header.add_css_class("flat")
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

        page_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        page_box.set_margin_start(16)
        page_box.set_margin_end(16)
        page_box.set_margin_top(16)
        page_box.set_margin_bottom(16)
        page_box.append(self._search_group)

        clamp = Adw.Clamp()
        clamp.set_child(page_box)
        self._stack.add_named(clamp, "__search__")

    def _populate_pages(self) -> None:
        """Build a stack page for each YAML page."""
        pages = self._config.get("pages", [])
        if not pages:
            self._show_empty()
            return

        self._nav_rows: dict[str, Gtk.ListBoxRow] = {}

        for page_cfg in pages:
            pid   = page_cfg.get("id", page_cfg.get("title", "").lower())
            title = page_cfg.get("title", pid)
            icon  = page_cfg.get("icon", "application-x-executable-symbolic")

            # Sidebar row
            row = self._make_nav_row(icon, title, pid)
            self._nav_list.append(row)
            self._nav_rows[pid] = row

            # Content page
            content = self._build_page_content(page_cfg)
            self._stack.add_named(content, pid)

        # ── Hardcoded: Config Manager (HCM) page ─────────────────────────────
        HCM_PID   = "__hcm__"
        HCM_ICON  = "󰦭"
        HCM_TITLE = "Config Manager"

        hcm_row = self._make_nav_row(HCM_ICON, HCM_TITLE, HCM_PID)
        self._nav_list.append(hcm_row)
        self._nav_rows[HCM_PID] = hcm_row

        hcm_page = hcm.ConfigManagerPage(self._toast_ov)
        hcm_page.set_vexpand(True)
        self._stack.add_named(hcm_page, HCM_PID)

        # Select first row
        first = self._nav_list.get_row_at_index(0)
        if first:
            self._nav_list.select_row(first)

    def _make_nav_row(self, icon_name: str, title: str, pid: str) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row.add_css_class("nav-row")

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.set_margin_top(8)
        box.set_margin_bottom(8)

        icon_widget = make_icon_widget(icon_name, ["nav-icon"])
        lbl = Gtk.Label(label=title, xalign=0)
        lbl.set_hexpand(True)
        box.append(icon_widget)
        box.append(lbl)

        row.set_child(box)
        row._page_title = title
        row._pid = pid

        return row

    def _build_page_content(self, page_cfg: dict) -> Gtk.Widget:
        """Build an Adw.PreferencesPage from YAML layout."""
        pref_page = Adw.PreferencesPage()
        pref_page.set_title(page_cfg.get("title", ""))

        for section_cfg in page_cfg.get("layout", []):
            group = self._build_section(section_cfg)
            if group:
                pref_page.add(group)

        return pref_page

    def _build_section(self, section_cfg: dict) -> Adw.PreferencesGroup | None:
        props = section_cfg.get("properties", {})
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

    def _on_nav_selected(self, listbox: Gtk.ListBox, row: Gtk.ListBoxRow) -> None:
        if row is None:
            return
        # Clear search
        self._search_entry.set_text("")
        pid = getattr(row, "_pid", None)
        if pid and self._stack.get_child_by_name(pid):
            self._stack.set_visible_child_name(pid)
            self._content_header.set_title_widget(
                Gtk.Label(label=getattr(row, "_page_title", ""))
            )

    # ── Search ────────────────────────────────────────────────────────────────

    def _on_search_changed(self, entry: Gtk.SearchEntry) -> None:
        if self._search_debounce:
            GLib.source_remove(self._search_debounce)
        self._search_debounce = GLib.timeout_add(
            SEARCH_DEBOUNCE, self._do_search, entry.get_text().strip()
        )

    def _on_search_stop(self, entry: Gtk.SearchEntry) -> None:
        self._search_entry.set_text("")
        # Restore previously selected page
        row = self._nav_list.get_selected_row()
        if row:
            self._on_nav_selected(self._nav_list, row)

    def _do_search(self, query: str) -> bool:
        self._search_debounce = 0
        if not query:
            row = self._nav_list.get_selected_row()
            if row:
                self._on_nav_selected(self._nav_list, row)
            return GLib.SOURCE_REMOVE

        self._stack.set_visible_child_name("__search__")
        self._content_header.set_title_widget(
            Gtk.Label(label=f'Results for "{query}"')
        )

        # Clear previous results
        while child := self._search_group.get_first_child():
            self._search_group.remove(child)

        ql = query.lower()
        matched = 0
        for entry in self._search_index:
            if ql in entry["title"].lower() or ql in entry["subtitle"].lower():
                widget = rows.build_row(entry["item"], self._ctx)
                if widget:
                    self._search_group.add(widget)
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

        return GLib.SOURCE_REMOVE

    # ── Keyboard shortcuts ────────────────────────────────────────────────────

    def _setup_shortcuts(self) -> None:
        ctrl = Gtk.EventControllerKey()
        ctrl.connect("key-pressed", self._on_key)
        self.add_controller(ctrl)

    def _on_key(self, ctrl, keyval, keycode, state) -> bool:
        mods = state & Gdk.ModifierType.CONTROL_MASK
        if mods and keyval == Gdk.KEY_r:
            self._reload()
            return True
        if keyval == Gdk.KEY_Escape:
            self._on_search_stop(self._search_entry)
            return True
        # Focus search on any printable key
        if not mods and keyval not in (Gdk.KEY_Tab, Gdk.KEY_Return):
            self._search_entry.grab_focus()
        return False

    def _reload(self) -> None:
        log.info("Reloading config…")
        # Clear everything
        while child := self._nav_list.get_first_child():
            self._nav_list.remove(child)
        while page := self._stack.get_first_child():
            self._stack.remove(page)
        self._search_index.clear()

        self._config = load_config()
        self._build_search_page()
        self._populate_pages()
        utility.toast(self._toast_ov, " Config reloaded")
        log.info("Reload complete")


# =============================================================================
# APPLICATION (Daemon mode)
# =============================================================================

class CloudCenter(Adw.Application):

    def __init__(self) -> None:
        super().__init__(
            application_id=APP_ID,
            flags=Gio.ApplicationFlags.DEFAULT_FLAGS,
        )
        self._window: CloudCenterWindow | None = None
        self._start_hidden_once = "--background" in sys.argv
        self.hold()  # prevent GApplication 10s timeout — daemon mode

    def do_activate(self) -> None:
        if self._window is None:
            self._window = CloudCenterWindow(self)
            self._window.connect("close-request", self._on_close)
            self._load_css()
            self._start_matugen_watcher()
        if self._start_hidden_once:
            # Used by restart scripts when we want daemon recovery with no pop-up.
            self._window.set_visible(False)
            self._start_hidden_once = False
            return
        self._window.present()

    def _on_close(self, win: CloudCenterWindow) -> bool:
        """Hide instead of destroy — instant relaunch next time."""
        win.set_visible(False)
        return True  # suppress destroy

    def _start_matugen_watcher(self) -> None:
        """Watch matugen color output and reload CSS when it changes."""
        if not MATUGEN_COLORS.exists():
            log.info("Matugen colors file not found, skipping watcher: %s", MATUGEN_COLORS)
            return
        gfile = Gio.File.new_for_path(str(MATUGEN_COLORS))
        self._matugen_monitor = gfile.monitor_file(Gio.FileMonitorFlags.NONE, None)
        self._matugen_monitor.connect("changed", self._on_matugen_changed)
        self._matugen_debounce: int = 0
        log.info("Watching matugen colors: %s", MATUGEN_COLORS)

    def _on_matugen_changed(
        self, monitor: Gio.FileMonitor, file: Gio.File,
        other_file: Gio.File, event_type: Gio.FileMonitorEvent
    ) -> None:
        if event_type not in (
            Gio.FileMonitorEvent.CHANGED,
            Gio.FileMonitorEvent.CREATED,
        ):
            return
        log.info("Matugen colors updated — scheduling reload")
        if self._matugen_debounce:
            GLib.source_remove(self._matugen_debounce)
        self._matugen_debounce = GLib.timeout_add(600, self._do_matugen_reload)

    def _do_matugen_reload(self) -> bool:
        """Reload CSS after matugen regenerates colors."""
        self._matugen_debounce = 0
        self._load_css()
        if self._window:
            utility.toast(self._window._toast_ov, "Theme updated")
        return GLib.SOURCE_REMOVE

    def _load_css(self) -> None:
        if not CSS_PATH.exists():
            return
        provider = Gtk.CssProvider()
        try:
            provider.load_from_path(str(CSS_PATH))
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
            )
        except Exception as e:
            log.error("CSS load failed: %s", e)


# =============================================================================
# ENTRY POINT
# =============================================================================

def main() -> int:
    return CloudCenter().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())