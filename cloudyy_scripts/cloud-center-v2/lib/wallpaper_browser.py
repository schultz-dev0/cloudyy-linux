"""
Online wallpaper browser row for Cloud Center.

Provides search + download for Wallhaven and WallpapersHome.
"""
from __future__ import annotations

import json
import logging
import os
import re
import threading
import webbrowser
from dataclasses import dataclass
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import TYPE_CHECKING, Any
from urllib.parse import urlencode, urljoin, urlparse
from urllib.request import Request, urlopen

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Adw, GLib, GdkPixbuf, Gtk

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


class _AnchorParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.items: list[dict[str, str]] = []
        self._in_anchor = False
        self._href = ""
        self._text: list[str] = []
        self._img_alt = ""
        self._img_src = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        amap = dict(attrs)
        if tag == "a":
            href = amap.get("href") or ""
            if href:
                self._in_anchor = True
                self._href = href
                self._text = []
                self._img_alt = ""
                self._img_src = ""
        elif tag == "img" and self._in_anchor:
            alt = amap.get("alt") or ""
            src = amap.get("src") or ""
            if alt:
                self._img_alt = alt.strip()
            if src:
                self._img_src = src.strip()

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._in_anchor:
            text = " ".join("".join(self._text).split()).strip()
            self.items.append({
                "href": self._href,
                "text": text,
                "alt": self._img_alt,
                "img": self._img_src,
            })
            self._in_anchor = False
            self._href = ""
            self._text = []
            self._img_alt = ""
            self._img_src = ""

    def handle_data(self, data: str) -> None:
        if self._in_anchor and data.strip():
            self._text.append(data)


class OnlineWallpaperBrowserRow(Adw.PreferencesRow):
    __gtype_name__ = "CCOnlineWallpaperBrowserRow"

    def __init__(self, props: dict[str, Any], _action: dict | None, ctx: "RowContext") -> None:
        super().__init__()
        self.set_activatable(False)

        self._ctx = ctx
        self._query = ""
        self._page = 1
        self._source = "all"
        self._busy = False
        self._results: list[WallpaperItem] = []
        self._thumb_sema = threading.BoundedSemaphore(6)

        def _expand(p: str) -> Path:
            return Path(os.path.expandvars(p)).expanduser()

        raw_dir = props.get("download_directory", "~/Wallpapers/Online")
        self._light_dir = _expand(props.get("light_directory", "~/Wallpapers/Light"))
        self._dark_dir  = _expand(props.get("dark_directory",  "~/Wallpapers/Dark"))
        self._download_dir = self._dark_dir   # default to dark
        self._wallpapershome_base = props.get("wallpapershome_base", "https://wallpapershome.com")
        self._wallpapershome_routes = [
            "nature",
            "abstract",
            "animals",
            "space",
            "travel",
            "best",
            "daily",
            "top",
            "aesthetic",
            "architecture",
            "creative",
            "decor",
            "mood",
            "objects",
            "people",
            "seasonal",
            "styles",
        ]

        self._build_widget(props)
        self._set_status("Ready")

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
            label=props.get("description", "Search and download from Wallhaven + WallpapersHome"),
            xalign=0,
        )
        subtitle.add_css_class("online-wall-subtitle")

        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title_box.set_hexpand(True)
        title_box.append(title)
        title_box.append(subtitle)

        self._source_badge = Gtk.Label(label="All Sources")
        self._source_badge.add_css_class("online-wall-source-badge")

        header.append(title_box)
        header.append(self._source_badge)

        dir_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        dir_box.add_css_class("online-wall-row")
        dir_lbl = Gtk.Label(label="Save to:", xalign=0)
        dir_lbl.add_css_class("dim-label")
        dir_box.append(dir_lbl)

        # Light / Dark toggle (linked button pair)
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

        self._save_dir_lbl = Gtk.Label(label=str(self._download_dir), xalign=0)
        self._save_dir_lbl.add_css_class("dim-label")
        self._save_dir_lbl.add_css_class("caption")
        self._save_dir_lbl.set_hexpand(True)
        self._save_dir_lbl.set_ellipsize(__import__("gi.repository.Pango", fromlist=["EllipsizeMode"]).EllipsizeMode.START)
        dir_box.append(self._save_dir_lbl)

        controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        controls.add_css_class("online-wall-row")
        self._search_entry = Gtk.SearchEntry()
        self._search_entry.set_hexpand(True)
        self._search_entry.set_placeholder_text("Search wallpapers")
        self._search_entry.connect("activate", self._on_search_clicked)

        self._source_combo = Gtk.DropDown.new_from_strings(["All", "Wallhaven", "WallpapersHome"])
        self._source_combo.set_selected(0)
        self._source_combo.connect("notify::selected", self._on_source_changed)

        prev_btn = Gtk.Button(label="Prev")
        prev_btn.connect("clicked", self._on_prev_clicked)
        next_btn = Gtk.Button(label="Next")
        next_btn.connect("clicked", self._on_next_clicked)
        search_btn = Gtk.Button(label="Search")
        search_btn.connect("clicked", self._on_search_clicked)

        controls.append(self._search_entry)
        controls.append(self._source_combo)
        controls.append(prev_btn)
        controls.append(next_btn)
        controls.append(search_btn)

        self._status = Gtk.Label(label="", xalign=0)
        self._status.add_css_class("dim-label")
        self._status.add_css_class("online-wall-status")

        self._list_box = Gtk.ListBox()
        self._list_box.set_selection_mode(Gtk.SelectionMode.NONE)
        self._list_box.add_css_class("boxed-list")
        self._list_box.add_css_class("online-wall-list")

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_min_content_height(int(props.get("height", 340)))
        scroll.set_child(self._list_box)
        scroll.add_css_class("online-wall-scroll")

        outer.append(header)
        outer.append(dir_box)
        outer.append(controls)
        outer.append(self._status)
        outer.append(scroll)

        self.set_child(outer)

    def _set_status(self, text: str) -> None:
        self._status.set_label(f"Page {self._page} | {text}")

    def _on_mode_toggled(self, _btn: Gtk.ToggleButton) -> None:
        if self._btn_light.get_active():
            self._download_dir = self._light_dir
        else:
            self._download_dir = self._dark_dir
        self._save_dir_lbl.set_label(str(self._download_dir))

    def _on_source_changed(self, combo: Gtk.DropDown, _pspec) -> None:
        idx = combo.get_selected()
        self._source = ["all", "wallhaven", "wallpapershome"][idx]
        self._source_badge.set_label(["All Sources", "Wallhaven", "WallpapersHome"][idx])

    def _on_prev_clicked(self, _btn: Gtk.Button) -> None:
        if self._busy:
            return
        if self._page > 1:
            self._page -= 1
            self._start_search()

    def _on_next_clicked(self, _btn: Gtk.Button) -> None:
        if self._busy:
            return
        self._page += 1
        self._start_search()

    def _on_search_clicked(self, _btn: Gtk.Widget) -> None:
        if self._busy:
            return
        self._page = max(1, self._page)
        self._start_search()

    def _start_search(self) -> None:
        self._busy = True
        self._query = self._search_entry.get_text().strip()
        self._set_status("Searching...")
        threading.Thread(target=self._search_worker, daemon=True).start()

    def _search_worker(self) -> None:
        try:
            items: list[WallpaperItem] = []
            if self._source in {"all", "wallhaven"}:
                items.extend(self._search_wallhaven(self._query, self._page))
            if self._source in {"all", "wallpapershome"}:
                items.extend(self._search_wallpapershome(self._query, self._page))
            GLib.idle_add(self._apply_results, items, None)
        except Exception as exc:
            GLib.idle_add(self._apply_results, [], str(exc))

    def _apply_results(self, items: list[WallpaperItem], err: str | None) -> bool:
        self._busy = False
        self._results = items

        while child := self._list_box.get_first_child():
            self._list_box.remove(child)

        if err:
            self._set_status(f"Error: {err}")
            return GLib.SOURCE_REMOVE

        self._set_status(f"Loaded {len(items)} wallpapers")

        for item in items:
            row = self._build_result_row(item)
            self._list_box.append(row)

        if not items:
            empty = Gtk.Label(label="No wallpapers found.")
            empty.add_css_class("dim-label")
            empty.set_margin_top(8)
            empty.set_margin_bottom(8)
            self._list_box.append(empty)

        return GLib.SOURCE_REMOVE

    def _build_result_row(self, item: WallpaperItem) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.set_margin_start(8)
        box.set_margin_end(8)
        box.set_margin_top(8)
        box.set_margin_bottom(8)

        thumb_host = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        thumb_host.add_css_class("online-wall-thumb-host")
        thumb_host.set_size_request(180, 102)
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
        dl_btn = Gtk.Button(label="Download")
        dl_btn.connect("clicked", self._on_download_clicked, item)
        btns.append(open_btn)
        btns.append(dl_btn)

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

            # Cover-scale: fill 180×102 without distortion
            scaled = self._scale_cover(pixbuf, 180, 102)
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
        pic.set_size_request(180, 102)
        pic.add_css_class("online-wall-thumb")
        host.append(pic)
        return GLib.SOURCE_REMOVE

    def _on_open_clicked(self, _btn: Gtk.Button, item: WallpaperItem) -> None:
        webbrowser.open(item.page_url)

    def _on_download_clicked(self, _btn: Gtk.Button, item: WallpaperItem) -> None:
        if self._busy:
            return
        self._busy = True
        self._set_status(f"Downloading {item.title}...")
        threading.Thread(target=self._download_worker, args=(item,), daemon=True).start()

    def _download_worker(self, item: WallpaperItem) -> None:
        try:
            image_url = item.image_url
            if not image_url and item.source == "WallpapersHome":
                image_url = self._resolve_wallpapershome_image(item.page_url)
            if not image_url:
                raise RuntimeError("No image URL available for this wallpaper")

            src_dir = self._download_dir / item.source.lower().replace(" ", "-")
            src_dir.mkdir(parents=True, exist_ok=True)

            parsed = urlparse(image_url)
            ext = Path(parsed.path).suffix.lower() or ".jpg"
            safe_title = re.sub(r"[^A-Za-z0-9._-]+", "_", item.title).strip("_") or "wallpaper"
            stamp = datetime.now(tz=timezone.utc).strftime("%Y%m%d_%H%M%S")
            file_path = src_dir / f"{safe_title}_{stamp}{ext}"

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
            })

            GLib.idle_add(self._download_done, f"Saved {file_path}", True)
        except Exception as exc:
            GLib.idle_add(self._download_done, f"Download failed: {exc}", False)

    def _download_done(self, msg: str, ok: bool) -> bool:
        self._busy = False
        self._set_status(msg)
        self._ctx.toast("Downloaded wallpaper" if ok else "Download failed")
        return GLib.SOURCE_REMOVE

    def _search_wallhaven(self, query: str, page: int) -> list[WallpaperItem]:
        def fetch(params: dict[str, str]) -> dict[str, Any]:
            url = "https://wallhaven.cc/api/v1/search?" + urlencode(params)
            return json.loads(self._http_get(url, binary=False))

        params = {"page": str(page), "sorting": "relevance", "purity": "100"}
        if query:
            params["q"] = query

        payload = fetch(params)
        data = payload.get("data", [])

        if not data and query:
            fallback_params = {
                "page": str(page),
                "sorting": "toplist",
                "purity": "100",
                "q": query,
            }
            payload = fetch(fallback_params)
            data = payload.get("data", [])

        if not data:
            fallback_params = {
                "page": str(page),
                "sorting": "toplist",
                "purity": "100",
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
        return out

    def _search_wallpapershome(self, query: str, page: int) -> list[WallpaperItem]:
        base = self._wallpapershome_base.rstrip("/")
        pool = self._wallpapershome_routes
        if query:
            q = query.lower().strip()
            matched = [r for r in pool if q in r]
            if matched:
                pool = matched

        route_idx = (max(page, 1) - 1) % len(pool)
        route_page = ((max(page, 1) - 1) // len(pool)) + 1
        route = pool[route_idx]
        url = f"{base}/{route}/?{urlencode({'page': str(route_page)})}"
        html = self._http_get(url, binary=False)

        parser = _AnchorParser()
        parser.feed(html)

        seen: set[str] = set()
        out: list[WallpaperItem] = []
        filtered_out: list[WallpaperItem] = []

        for anchor in parser.items:
            href = anchor.get("href", "")
            if not href:
                continue
            href_low = href.lower()
            has_thumb = bool(anchor.get("img"))
            if not has_thumb and "wallpaper" not in href_low and not href_low.endswith(".html"):
                continue

            page_url = urljoin(base + "/", href)
            if page_url in seen:
                continue
            seen.add(page_url)

            title = anchor.get("alt") or anchor.get("text") or "WallpapersHome"
            title = title.strip()
            item = WallpaperItem(
                source="WallpapersHome",
                title=title,
                page_url=page_url,
                image_url=None,
                preview_url=urljoin(base + "/", anchor.get("img", "")) if anchor.get("img") else None,
                resolution=self._extract_resolution(title),
            )

            if query and query.lower() not in title.lower() and query.lower() not in page_url.lower():
                filtered_out.append(item)
                continue

            out.append(item)

            if len(out) >= 120:
                break

        if out:
            return out
        return filtered_out[:120]

    def _resolve_wallpapershome_image(self, page_url: str) -> str | None:
        html = self._http_get(page_url, binary=False)

        m = re.search(r'<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)["\']', html, re.I)
        if m:
            return urljoin(page_url, m.group(1))

        m = re.search(r'href=["\']([^"\']+\.(?:jpg|jpeg|png|webp))["\']', html, re.I)
        if m:
            return urljoin(page_url, m.group(1))

        return None

    def _extract_resolution(self, text: str) -> str:
        m = re.search(r"\b(\d{3,5}x\d{3,5})\b", text)
        return m.group(1) if m else ""

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
