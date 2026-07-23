"""
Cloud Center — lib/ccd/online_wallpapers.py
Wallhaven search, disk-cached thumbnails, and download/apply for the online
wallpaper browser page. Same disk-cache-thumbnail pattern as model.py's
local wallpaper_thumb (lib/ccd/model.py), just keyed by Wallhaven id instead
of path+mtime since these are immutable remote images.
"""
from __future__ import annotations

import logging
import threading
from pathlib import Path

import requests

import lib.utility as utility
from lib.ccd import actions, model, protocol

log = logging.getLogger(__name__)

THUMB_DIR = utility.CACHE_DIR / "online_thumbs"
API_URL = "https://wallhaven.cc/api/v1/search"
TIMEOUT = 15


def _cache_thumb(wallhaven_id: str, url: str) -> str:
    if not wallhaven_id or not url:
        return ""
    cached = THUMB_DIR / f"{wallhaven_id}.jpg"
    if cached.exists():
        return str(cached)
    try:
        THUMB_DIR.mkdir(parents=True, exist_ok=True)
        resp = requests.get(url, timeout=TIMEOUT)
        resp.raise_for_status()
        cached.write_bytes(resp.content)
        return str(cached)
    except Exception as e:
        log.warning("online thumb fetch failed for %s: %s", url, e)
        return ""


def search(params: dict) -> dict:
    """Wallhaven search. No query -> hot/toplist browse; query -> relevance."""
    query = str(params.get("query", "")).strip()
    sort = str(params.get("sort", "hot"))  # "hot" | "toplist", ignored if query set
    page = max(1, int(params.get("page", 1)))
    min_res = str(params.get("min_res", "")).strip()  # e.g. "1920x1080", Wallhaven's own "atleast" filter

    api_params = {"purity": "100", "page": page}
    if query:
        api_params["q"] = query
        api_params["sorting"] = "relevance"
    else:
        api_params["sorting"] = "toplist" if sort == "toplist" else "hot"
        if api_params["sorting"] == "toplist":
            api_params["topRange"] = "1M"
    if min_res:
        api_params["atleast"] = min_res

    try:
        resp = requests.get(API_URL, params=api_params, timeout=TIMEOUT)
        resp.raise_for_status()
        data = resp.json()
    except Exception as e:
        log.warning("wallhaven search failed: %s", e)
        return {"results": [], "has_more": False, "error": str(e)}

    results = []
    for item in data.get("data", []):
        wid = str(item.get("id", ""))
        thumb_url = (item.get("thumbs") or {}).get("small", "")
        results.append({
            "id": wid,
            "thumb": _cache_thumb(wid, thumb_url),
            "full_url": item.get("path", ""),
            "page_url": item.get("url", ""),
            "resolution": item.get("resolution", ""),
        })

    meta = data.get("meta") or {}
    has_more = meta.get("current_page", page) < meta.get("last_page", page)
    return {"results": results, "has_more": has_more}


def apply_or_download(params: dict) -> dict:
    """Download a Wallhaven result into the mode-specific pool; optionally apply it.

    Mirrors the GTK browser's convention: sequential zero-padded filenames in
    the target directory, same base apply_command template as the local
    picker (plus a `--mode` flag the local picker's template doesn't pass).
    `mode` ("light"/"dark") picks light_directory vs dark_directory *and*,
    when applying, is passed to theme_controller.sh so applying a wallpaper
    you explicitly chose for the Dark pool also switches system theme mode
    to match, rather than silently applying it under whatever mode happened
    to already be active. Falls back to the current system theme_mode if
    omitted or invalid.
    """
    url = str(params.get("url", ""))
    apply_command = str(params.get("apply_command", ""))
    do_apply = bool(params.get("apply", True))
    mode = str(params.get("mode", "")).lower()
    if mode not in ("light", "dark"):
        mode = model.theme_mode()
    directory = str(
        params.get("dark_directory" if mode == "dark" else "light_directory", "")
    )
    if not url or not directory:
        raise ValueError("url and a light_directory/dark_directory are required")

    def worker() -> None:
        try:
            dest_dir = Path(directory).expanduser()
            dest_dir.mkdir(parents=True, exist_ok=True)
            ext = Path(url).suffix or ".jpg"
            existing = [int(p.stem) for p in dest_dir.glob("*") if p.stem.isdigit()]
            dest = dest_dir / f"{(max(existing) + 1) if existing else 0:04d}{ext}"

            resp = requests.get(url, timeout=30)
            resp.raise_for_status()
            dest.write_bytes(resp.content)

            if do_apply and apply_command:
                cmd = apply_command.replace("{path}", str(dest)).replace("{mode}", mode)
                actions.run_command(cmd, "wallpapers/online")
            else:
                protocol.send_event({"event": "toast", "text": f"Saved {dest.name}"})
        except Exception as e:
            log.warning("online wallpaper download failed: %s", e)
            protocol.send_event({"event": "toast", "text": f"Download failed: {e}"})

    threading.Thread(target=worker, daemon=True).start()
    return {"started": True}


def get_theme_mode(params: dict) -> dict:
    return {"mode": model.theme_mode()}


protocol.register("search_wallpapers_online", search)
protocol.register("apply_wallpaper_online", apply_or_download)
protocol.register("get_theme_mode", get_theme_mode)
