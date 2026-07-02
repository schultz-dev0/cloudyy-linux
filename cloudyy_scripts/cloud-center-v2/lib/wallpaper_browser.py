"""
Online wallpaper browser row for Cloud Center.

Provides search + download for Wallhaven.
"""
from __future__ import annotations

import json
import logging
import os
import threading
import webbrowser
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING, Any
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Adw, GLib, GdkPixbuf, Gtk
import lib.utility as utility

if TYPE_CHECKING:
    from lib.rows import RowContext

log = logging.getLogger(__name__)

_USER_AGENT = "cloud-center-wallpaper-browser/1.0"
_LIBRARY_PATH = Path.home() / ".config" / "cloud-center" / "wallpaper_browser" / "library.json"
_HTTP_TIMEOUT = 15
_BROWSER_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}


@dataclass
class WallpaperItem:
    source: str
    title: str
    page_url: str
    image_url: str | None = None
    preview_url: str | None = None
    resolution: str = ""


class OnlineWallpaperBrowserRow(Adw.PreferencesRow):
    __gtype_name__ = "CCOnlineWallpaperBrowserRow"

    def __init__(self, props: dict[str, Any], _action: dict | None, ctx: "RowContext") -> None:
        super().__init__()
        self.set_activatable(False)

        self._ctx = ctx
        self._query = ""
        self._next_page = 1
        self._has_more = True
        self._mode = "dark"
        self._busy = False
        self._results: list[WallpaperItem] = []
        self._thumb_sema = threading.BoundedSemaphore(6)
        self._thumb_cache: dict[str, GdkPixbuf.Pixbuf] = {}

        def _expand(p: str) -> Path:
            return Path(os.path.expandvars(p)).expanduser()

        self._light_dir = _expand(props.get("light_directory", "~/Wallpapers/user_wallpapers/Light"))
        self._dark_dir = _expand(props.get("dark_directory", "~/Wallpapers/user_wallpapers/Dark"))
        self._download_dir = self._dark_dir
        self._per_page = max(1, min(24, int(props.get("per_page", 24))))
        self._apply_cmd_tmpl = props.get("apply_command", "~/cloudyy_scripts/theme_controller.sh set-image {path}")
        self._sorting = "hot"
        self._top_range = "1w"
        self._ratio = ""
        self._atleast = ""

        self._build_widget(props)
        GLib.idle_add(self._start_search, True)

    def _build_widget(self, props: dict[str, Any]) -> None:
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        outer.add_css_class("online-wall-browser")
        outer.set_margin_start(10)
        outer.set_margin_end(10)
        outer.set_margin_top(10)
        outer.set_margin_bottom(10)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        header.add_css_class("online-wall-header")
        title = Gtk.Label(label=props.get("title", "Online Wallpaper Browser"), xalign=0)
        title.add_css_class("online-wall-title")
        title.set_hexpand(True)

        subtitle = Gtk.Label(
            label=props.get("description", "Search and download from Wallhaven"),
            xalign=0,
        )
        subtitle.add_css_class("online-wall-subtitle")

        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title_box.set_hexpand(True)
        title_box.append(title)
        title_box.append(subtitle)

        header.append(title_box)

        dir_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        dir_box.add_css_class("online-wall-row")
        dir_lbl = Gtk.Label(label="Mode:", xalign=0)
        dir_lbl.add_css_class("dim-label")
        dir_box.append(dir_lbl)

        mode_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        mode_box.add_css_class("linked")
        self._btn_dark = Gtk.ToggleButton(label="Dark")
        self._btn_light = Gtk.ToggleButton(label="Light", group=self._btn_dark)
        self._btn_dark.set_active(True)
        self._btn_dark.connect("toggled", self._on_mode_toggled)
        self._btn_light.connect("toggled", self._on_mode_toggled)
        mode_box.append(self._btn_dark)
        mode_box.append(self._btn_light)
        dir_box.append(mode_box)

        controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        controls.add_css_class("online-wall-row")
        self._search_entry = Gtk.SearchEntry()
        self._search_entry.set_hexpand(True)
        self._search_entry.set_placeholder_text("Search wallpapers")
        self._search_entry.connect("activate", self._on_search_clicked)

        search_btn = Gtk.Button(label="Search")
        search_btn.connect("clicked", self._on_search_clicked)

        controls.append(self._search_entry)
        controls.append(search_btn)

        tags = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        tags.add_css_class("online-wall-row")
        tags.add_css_class("online-wall-tags")
        self._chips: dict[str, Gtk.ToggleButton] = {}

        def _chip(label: str, key: str, active: bool = False) -> Gtk.ToggleButton:
            btn = Gtk.ToggleButton(label=label)
            btn.add_css_class("pill")
            btn.set_active(active)
            btn.connect("toggled", self._on_chip_toggled, key)
            self._chips[key] = btn
            tags.append(btn)
            return btn

        _chip("Hot", "sort:hot", active=True)
        _chip("Top Week", "top:1w")
        _chip("Top Month", "top:1M")
        _chip("16:9", "ratio:16x9")
        _chip("21:9", "ratio:21x9")
        _chip("1080p+", "atleast:1920x1080")
        _chip("4K+", "atleast:3840x2160")

        self._status = Gtk.Label(label="", xalign=0)
        self._status.add_css_class("dim-label")
        self._status.add_css_class("online-wall-status")

        self._list_box = Gtk.ListBox()
        self._list_box.set_selection_mode(Gtk.SelectionMode.NONE)
        self._list_box.add_css_class("boxed-list")
        self._list_box.add_css_class("online-wall-list")
        self._list_box.set_hexpand(True)

        self._scroll = Gtk.ScrolledWindow()
        self._scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self._scroll.set_min_content_height(int(props.get("height", 640)))
        self._scroll.set_child(self._list_box)
        self._scroll.add_css_class("online-wall-scroll")

        self._load_more_btn = Gtk.Button(label="Load more")
        self._load_more_btn.connect("clicked", self._on_load_more_clicked)
        self._load_more_btn.set_halign(Gtk.Align.CENTER)
        self._load_more_btn.set_margin_top(6)
        self._load_more_btn.set_margin_bottom(6)

        outer.append(header)
        outer.append(dir_box)
        outer.append(controls)
        outer.append(tags)
        outer.append(self._status)
        outer.append(self._scroll)
        outer.append(self._load_more_btn)

        self.set_child(outer)

    def _set_status(self, text: str) -> None:
        self._status.set_label(text)

    def _on_mode_toggled(self, _btn: Gtk.ToggleButton) -> None:
        if self._btn_light.get_active():
            self._mode = "light"
            self._download_dir = self._light_dir
        else:
            self._mode = "dark"
            self._download_dir = self._dark_dir

    def _on_chip_toggled(self, btn: Gtk.ToggleButton, key: str) -> None:
        if not btn.get_active():
            return

        group, value = key.split(":", 1)
        for k, chip in self._chips.items():
            if k == key:
                continue
            if k.startswith(group + ":"):
                chip.set_active(False)

        if group == "sort":
            self._sorting = value
            self._top_range = "1w"
        elif group == "top":
            self._sorting = "toplist"
            self._top_range = value
        elif group == "ratio":
            self._ratio = value
        elif group == "atleast":
            self._atleast = value

        self._start_search(reset=True)

    def _on_search_clicked(self, _btn: Gtk.Widget) -> None:
        self._start_search(reset=True)

    def _on_load_more_clicked(self, _btn: Gtk.Button) -> None:
        self._start_search(reset=False)

    def _start_search(self, reset: bool = False) -> bool:
        if self._busy:
            return GLib.SOURCE_REMOVE
        if reset:
            self._next_page = 1
            self._has_more = True
            self._results = []
            self._query = self._search_entry.get_text().strip()
            while child := self._list_box.get_first_child():
                self._list_box.remove(child)
            vadj = self._scroll.get_vadjustment()
            if vadj is not None:
                vadj.set_value(vadj.get_lower())
        if not self._has_more:
            return GLib.SOURCE_REMOVE

        self._busy = True
        self._load_more_btn.set_sensitive(False)
        self._set_status("")
        page = self._next_page
        query = self._query
        threading.Thread(target=self._search_worker, args=(query, page), daemon=True).start()
        return GLib.SOURCE_REMOVE

    def _search_worker(self, query: str, page: int) -> None:
        try:
            items, has_more = self._search_wallhaven(query, page)
            GLib.idle_add(self._apply_results, items, has_more, page, None)
        except Exception as exc:
            GLib.idle_add(self._apply_results, [], self._has_more, page, str(exc))

    def _apply_results(self, items: list[WallpaperItem], has_more: bool, page: int, err: str | None) -> bool:
        self._busy = False
        self._load_more_btn.set_sensitive(True)

        if err:
            self._set_status(f"Error: {err}")
            return GLib.SOURCE_REMOVE

        self._results.extend(items)
        self._has_more = has_more
        self._next_page = page + 1

        for item in items:
            row = self._build_result_row(item)
            self._list_box.append(row)

        if not self._results:
            empty = Gtk.Label(label="No wallpapers found.")
            empty.add_css_class("dim-label")
            empty.set_margin_top(8)
            empty.set_margin_bottom(8)
            self._list_box.append(empty)
            self._has_more = False

        if not self._has_more:
            self._load_more_btn.set_sensitive(False)
        self._set_status("")
        return GLib.SOURCE_REMOVE

    def _build_result_row(self, item: WallpaperItem) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.set_margin_start(8)
        box.set_margin_end(8)
        box.set_margin_top(8)
        box.set_margin_bottom(8)

        thumb_host = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        thumb_host.add_css_class("online-wall-thumb-host")
        thumb_host.set_size_request(260, 146)
        placeholder = Gtk.Image.new_from_icon_name("image-x-generic-symbolic")
        placeholder.add_css_class("online-wall-thumb-placeholder")
        thumb_host.append(placeholder)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        content.set_hexpand(True)

        t = Gtk.Label(label=item.title, xalign=0)
        t.add_css_class("online-wall-result-title")
        t.set_wrap(True)
        meta = Gtk.Label(
            label=f"{item.source} | {item.resolution or 'Unknown resolution'}",
            xalign=0,
        )
        meta.add_css_class("dim-label")

        btns = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        open_btn = Gtk.Button(label="Open")
        open_btn.connect("clicked", self._on_open_clicked, item)
        prev_btn = Gtk.Button(label="Preview")
        prev_btn.connect("clicked", self._on_preview_clicked, item)
        dl_btn = Gtk.Button(label="Download")
        dl_btn.connect("clicked", self._on_download_clicked, item)
        apply_btn = Gtk.Button(label="Apply")
        apply_btn.add_css_class("suggested-action")
        apply_btn.connect("clicked", self._on_apply_clicked, item)
        btns.append(open_btn)
        btns.append(prev_btn)
        btns.append(dl_btn)
        btns.append(apply_btn)

        content.append(t)
        content.append(meta)
        content.append(btns)

        box.append(thumb_host)
        box.append(content)

        frame = Gtk.Frame()
        frame.add_css_class("card")
        frame.add_css_class("online-wall-result-card")
        frame.set_child(box)

        preview = item.preview_url or item.image_url
        if preview:
            threading.Thread(
                target=self._load_thumbnail,
                args=(preview, thumb_host),
                daemon=True,
            ).start()

        return frame

    @staticmethod
    def _scale_cover(
        pixbuf: GdkPixbuf.Pixbuf, w: int, h: int
    ) -> GdkPixbuf.Pixbuf | None:
        """Scale pixbuf to fill w×h without stretching (cover, centred crop)."""
        sw, sh = pixbuf.get_width(), pixbuf.get_height()
        if sw == 0 or sh == 0:
            return None
        scale = max(w / sw, h / sh)
        nw, nh = max(1, int(sw * scale)), max(1, int(sh * scale))
        scaled = pixbuf.scale_simple(nw, nh, GdkPixbuf.InterpType.BILINEAR)
        if scaled is None:
            return None
        x_off = min((nw - w) // 2, nw - w) if nw > w else 0
        y_off = min((nh - h) // 2, nh - h) if nh > h else 0
        x_off, y_off = max(0, x_off), max(0, y_off)
        out_w = min(w, nw - x_off)
        out_h = min(h, nh - y_off)
        if out_w <= 0 or out_h <= 0:
            return scaled
        return scaled.new_subpixbuf(x_off, y_off, out_w, out_h)

    def _load_thumbnail(self, preview_url: str, host: Gtk.Box) -> None:
        if not self._thumb_sema.acquire(timeout=0.25):
            return
        try:
            data = self._http_get(preview_url, binary=True)
            if not isinstance(data, bytes) or not data:
                return

            loader = GdkPixbuf.PixbufLoader()
            loader.write(data)
            loader.close()
            pixbuf = loader.get_pixbuf()
            if pixbuf is None:
                return

            self._thumb_cache[preview_url] = pixbuf

            scaled = self._scale_cover(pixbuf, 260, 146)
            if scaled is None:
                return

            GLib.idle_add(self._set_thumbnail_widget, host, scaled)
        except Exception:
            return
        finally:
            self._thumb_sema.release()

    def _set_thumbnail_widget(self, host: Gtk.Box, pixbuf: GdkPixbuf.Pixbuf) -> bool:
        if host.get_parent() is None:
            return GLib.SOURCE_REMOVE
        while child := host.get_first_child():
            host.remove(child)

        pic = Gtk.Picture.new_for_pixbuf(pixbuf)
        try:
            pic.set_content_fit(Gtk.ContentFit.COVER)
        except AttributeError:
            pic.set_can_shrink(True)
        pic.set_size_request(260, 146)
        pic.add_css_class("online-wall-thumb")
        host.append(pic)
        return GLib.SOURCE_REMOVE

    def _on_open_clicked(self, _btn: Gtk.Button, item: WallpaperItem) -> None:
        webbrowser.open(item.page_url)

    def _on_preview_clicked(self, _btn: Gtk.Button, item: WallpaperItem) -> None:
        key = item.preview_url or item.image_url
        pixbuf = self._thumb_cache.get(key) if key else None

        dialog = Adw.Dialog(title=item.title or "Preview")

        toolbar_view = Adw.ToolbarView()
        toolbar_view.add_top_bar(Adw.HeaderBar())

        if pixbuf is None:
            lbl = Gtk.Label(label="Thumbnail not loaded yet — wait a moment and try again.")
            lbl.add_css_class("dim-label")
            lbl.set_margin_top(24)
            lbl.set_margin_bottom(24)
            lbl.set_margin_start(16)
            lbl.set_margin_end(16)
            toolbar_view.set_content(lbl)
            dialog.set_content_width(480)
        else:
            sw, sh = pixbuf.get_width(), pixbuf.get_height()
            scale = min(960 / max(sw, 1), 600 / max(sh, 1))
            if scale < 1:
                scale = 1
            nw, nh = max(1, int(sw * scale)), max(1, int(sh * scale))
            scaled = pixbuf.scale_simple(nw, nh, GdkPixbuf.InterpType.BILINEAR)
            pic = Gtk.Picture.new_for_pixbuf(scaled)
            pic.set_can_shrink(False)
            toolbar_view.set_content(pic)
            dialog.set_content_width(nw)
            dialog.set_content_height(nh)

        dialog.set_child(toolbar_view)
        dialog.present(self)

    def _on_download_clicked(self, _btn: Gtk.Button, item: WallpaperItem) -> None:
        if self._busy:
            return
        self._busy = True
        self._load_more_btn.set_sensitive(False)
        self._set_status(f"Downloading {item.title}...")
        threading.Thread(target=self._download_worker, args=(item,), daemon=True).start()

    def _on_apply_clicked(self, _btn: Gtk.Button, item: WallpaperItem) -> None:
        if self._busy:
            return
        self._busy = True
        self._load_more_btn.set_sensitive(False)
        self._set_status(f"Applying {item.title}...")
        threading.Thread(target=self._apply_worker, args=(item,), daemon=True).start()

    _IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}

    def _next_filename(self, directory: Path, ext: str) -> str:
        """Next sequential zero-padded name in a flat mode directory."""
        nums = [
            int(f.stem)
            for f in directory.iterdir()
            if f.is_file() and f.suffix.lower() in self._IMAGE_EXTS and f.stem.isdigit()
        ]
        n = (max(nums) + 1) if nums else 1
        width = max(3, len(str(n)))
        return f"{n:0{width}d}{ext}"

    def _download_worker(self, item: WallpaperItem) -> None:
        try:
            file_path = self._download_item(item)
            GLib.idle_add(self._download_done, f"Saved {file_path}", True)
        except Exception as exc:
            GLib.idle_add(self._download_done, f"Download failed: {exc}", False)

    def _apply_worker(self, item: WallpaperItem) -> None:
        try:
            file_path = self._download_item(item)
            cmd = self._apply_cmd_tmpl.replace("{path}", str(file_path))
            if not utility.execute_command(cmd):
                raise RuntimeError("Could not execute apply command")
            GLib.idle_add(self._apply_done, f"Applied {file_path}", True)
        except Exception as exc:
            GLib.idle_add(self._apply_done, f"Apply failed: {exc}", False)

    def _download_item(self, item: WallpaperItem) -> Path:
        image_url = item.image_url
        if not image_url:
            raise RuntimeError("No image URL available for this wallpaper")

        src_dir = self._download_dir.resolve()
        src_dir.mkdir(parents=True, exist_ok=True)

        parsed = urlparse(image_url)
        ext = Path(parsed.path).suffix.lower() or ".jpg"
        if ext not in self._IMAGE_EXTS:
            ext = ".jpg"
        file_path = src_dir / self._next_filename(src_dir, ext)

        data = self._http_get(image_url, binary=True)
        if not isinstance(data, bytes):
            raise RuntimeError("Failed to fetch image bytes")
        file_path.write_bytes(data)

        self._append_library({
            "title": item.title,
            "source": item.source,
            "page_url": item.page_url,
            "image_url": image_url,
            "resolution": item.resolution,
            "saved_path": str(file_path),
            "downloaded_at": datetime.now(tz=timezone.utc).isoformat(),
            "mode": self._mode,
        })
        return file_path

    def _download_done(self, msg: str, ok: bool) -> bool:
        self._busy = False
        self._load_more_btn.set_sensitive(self._has_more)
        self._set_status("" if ok else msg)
        self._ctx.toast("Downloaded wallpaper" if ok else "Download failed")
        return GLib.SOURCE_REMOVE

    def _apply_done(self, msg: str, ok: bool) -> bool:
        self._busy = False
        self._load_more_btn.set_sensitive(self._has_more)
        self._set_status("" if ok else msg)
        self._ctx.toast("Applied wallpaper" if ok else "Apply failed")
        return GLib.SOURCE_REMOVE

    def _search_wallhaven(self, query: str, page: int) -> tuple[list[WallpaperItem], bool]:
        def fetch(params: dict[str, str]) -> dict[str, Any]:
            url = "https://wallhaven.cc/api/v1/search?" + urlencode(params)
            return json.loads(self._http_get(url, binary=False))

        if query:
            params: dict[str, str] = {
                "page": str(page),
                "sorting": "relevance",
                "purity": "100",
                "q": query,
                "per_page": str(self._per_page),
            }
        else:
            params = {
                "page": str(page),
                "sorting": self._sorting,
                "purity": "100",
                "per_page": str(self._per_page),
            }
            if self._sorting == "toplist":
                params["topRange"] = self._top_range
        if self._ratio:
            params["ratios"] = self._ratio
        if self._atleast:
            params["atleast"] = self._atleast

        payload = fetch(params)
        data = payload.get("data", [])

        if not data and query:
            fallback_params = {
                "page": str(page),
                "sorting": "hot",
                "purity": "100",
                "per_page": str(self._per_page),
            }
            payload = fetch(fallback_params)
            data = payload.get("data", [])

        out: list[WallpaperItem] = []
        for entry in data:
            out.append(
                WallpaperItem(
                    source="Wallhaven",
                    title=f"Wallhaven {entry.get('id', '')}".strip(),
                    page_url=entry.get("url", ""),
                    image_url=entry.get("path"),
                    preview_url=(entry.get("thumbs") or {}).get("small"),
                    resolution=entry.get("resolution", ""),
                )
            )
        meta = payload.get("meta") or {}
        current_page = int(meta.get("current_page") or page)
        last_page = int(meta.get("last_page") or current_page)
        has_more = current_page < last_page
        return out, has_more

    def _append_library(self, entry: dict[str, Any]) -> None:
        _LIBRARY_PATH.parent.mkdir(parents=True, exist_ok=True)
        data: list[dict[str, Any]] = []
        if _LIBRARY_PATH.exists():
            try:
                data = json.loads(_LIBRARY_PATH.read_text(encoding="utf-8"))
                if not isinstance(data, list):
                    data = []
            except Exception:
                data = []

        data.insert(0, entry)
        _LIBRARY_PATH.write_text(json.dumps(data, indent=2), encoding="utf-8")

    def _http_get(self, url: str, *, binary: bool) -> str | bytes:
        headers = dict(_BROWSER_HEADERS)
        if any(host in url for host in ("wallhaven.cc", "w.wallhaven.cc", "th.wallhaven.cc")):
            headers["User-Agent"] = _USER_AGENT

        req = Request(url, headers=headers)
        with urlopen(req, timeout=_HTTP_TIMEOUT) as r:
            payload = r.read()

        if binary:
            return payload
        return payload.decode("utf-8", errors="ignore")
