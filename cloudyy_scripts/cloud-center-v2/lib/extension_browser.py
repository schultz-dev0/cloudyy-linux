"""
Native Zsh Extension Browser Row for Cloud Center.
"""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gtk

log = logging.getLogger(__name__)

ACTIVE_ZSH_PLUGINS_FILE = Path.home() / ".config/cloud-center/settings/terminal/active_zsh_plugins.txt"
ZSH_PLUGINS_DIR = Path.home() / ".config/zsh/oh-my-zsh/plugins"
CUSTOM_PLUGINS_DIR = Path.home() / ".config/zsh/oh-my-zsh/custom/plugins"

class ExtensionBrowserRow(Adw.PreferencesRow):
    __gtype_name__ = "CCExtensionBrowserRow"

    def __init__(self, props: dict[str, Any], _action: dict | None, ctx) -> None:
        super().__init__()
        self.set_activatable(False)
        self._ctx = ctx

        self._plugins: list[dict] = []
        self._active_plugins: set[str] = set()
        self._show_enabled_only: bool = False

        self._build_widget(props)
        self._load_plugins()

    def _build_widget(self, props: dict[str, Any]) -> None:
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        outer.add_css_class("online-wall-browser")
        outer.set_margin_start(10)
        outer.set_margin_end(10)
        outer.set_margin_top(10)
        outer.set_margin_bottom(10)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title_box.set_hexpand(True)
        
        title = Gtk.Label(label=props.get("title", "Extension Browser"), xalign=0)
        title.add_css_class("online-wall-title")
        subtitle = Gtk.Label(label=props.get("description", "Browse and manage Zsh extensions"), xalign=0)
        subtitle.add_css_class("online-wall-subtitle")
        
        title_box.append(title)
        title_box.append(subtitle)
        header.append(title_box)

        # Filter toggle
        self._filter_btn = Gtk.ToggleButton(label="Enabled Only")
        self._filter_btn.set_valign(Gtk.Align.CENTER)
        self._filter_btn.connect("toggled", self._on_filter_toggled)
        header.append(self._filter_btn)

        outer.append(header)

        # Search bar
        self._search_entry = Gtk.SearchEntry()
        self._search_entry.set_hexpand(True)
        self._search_entry.set_placeholder_text("Search Zsh plugins...")
        self._search_entry.connect("search-changed", self._on_search_changed)
        outer.append(self._search_entry)

        # Results list
        self._listbox = Gtk.ListBox()
        self._listbox.add_css_class("boxed-list")
        self._listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_min_content_height(400)
        scroll.set_child(self._listbox)
        outer.append(scroll)

        self.set_child(outer)

    def _load_plugins(self) -> None:
        self._active_plugins.clear()
        if ACTIVE_ZSH_PLUGINS_FILE.exists():
            with open(ACTIVE_ZSH_PLUGINS_FILE, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        self._active_plugins.add(line)

        self._plugins.clear()
        
        def scan_dir(d: Path):
            if not d.exists():
                return
            for p in d.iterdir():
                if p.is_dir() and not p.name.startswith('.'):
                    desc = ""
                    readme = p / "README.md"
                    if readme.exists():
                        try:
                            with open(readme, 'r', encoding='utf-8', errors='ignore') as f:
                                for line in f:
                                    line = line.strip()
                                    if line and not line.startswith('#') and not line.startswith('['):
                                        desc = line[:100] + ("..." if len(line) > 100 else "")
                                        break
                        except Exception:
                            pass
                    self._plugins.append({
                        "name": p.name,
                        "desc": desc,
                        "enabled": p.name in self._active_plugins
                    })

        scan_dir(ZSH_PLUGINS_DIR)
        scan_dir(CUSTOM_PLUGINS_DIR)
        
        # Sort so enabled plugins show first, then alphabetical
        self._plugins.sort(key=lambda x: (not x["enabled"], x["name"]))
        self._render_results()

    def _on_search_changed(self, entry: Gtk.SearchEntry) -> None:
        self._render_results(entry.get_text().strip().lower())

    def _on_filter_toggled(self, btn: Gtk.ToggleButton) -> None:
        self._show_enabled_only = btn.get_active()
        self._render_results(self._search_entry.get_text().strip().lower())

    def _render_results(self, query: str = "") -> None:
        # Clear existing
        while child := self._listbox.get_first_child():
            self._listbox.remove(child)

        count = 0
        for p in self._plugins:
            if self._show_enabled_only and not p["enabled"]:
                continue

            if query and query not in p["name"].lower() and query not in p["desc"].lower():
                continue

            row = Adw.ActionRow(title=p["name"], subtitle=p["desc"] or "No description available.")
            switch = Gtk.Switch()
            switch.set_active(p["enabled"])
            switch.set_valign(Gtk.Align.CENTER)
            
            # Using default arg to capture current plugin name in lambda
            switch.connect("notify::active", lambda sw, param, name=p["name"]: self._on_plugin_toggled(name, sw.get_active()))
            
            row.add_suffix(switch)
            self._listbox.append(row)
            
            count += 1
            if count >= 100: # Limit to 100 to keep UI fast
                break

        if count == 0:
            placeholder = Adw.ActionRow(title="No plugins found")
            placeholder.add_css_class("dim-label")
            self._listbox.append(placeholder)
                
    def _on_plugin_toggled(self, name: str, state: bool) -> None:
        if state:
            self._active_plugins.add(name)
            # Update the source dict too so sorting remains somewhat consistent
            for p in self._plugins:
                if p["name"] == name:
                    p["enabled"] = True
        else:
            self._active_plugins.discard(name)
            for p in self._plugins:
                if p["name"] == name:
                    p["enabled"] = False
            
        ACTIVE_ZSH_PLUGINS_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(ACTIVE_ZSH_PLUGINS_FILE, 'w') as f:
            for p in sorted(self._active_plugins):
                f.write(f"{p}\n")
