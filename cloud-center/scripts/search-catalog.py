#!/usr/bin/env python3
"""Export settings search metadata without device queries or backend startup."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml

CC_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CC_ROOT))
from lib.ccd.page_metadata import NATIVE_PAGES  # noqa: E402


def build_catalog(config_path: Path = CC_ROOT / "config.yaml") -> list[dict]:
    config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    rows = []
    for page in [*config.get("pages", []), *NATIVE_PAGES]:
        page_id = page.get("id", "")
        title = page.get("title", "")
        if not page_id or not title:
            continue
        rows.append({"id": f"settings.{page_id}", "label": title, "page": page_id,
                     "icon": page.get("icon", ""), "keywords": ["settings", title, *page.get("keywords", [])],
                     "context": "Cloud Center"})
        for section_index, section in enumerate(page.get("layout", [])):
            section_title = (section.get("properties") or {}).get("title", "")
            for item_index, item in enumerate(section.get("items", [])):
                props = item.get("properties") or {}
                if not props.get("title") or item.get("type") == "label":
                    continue
                rows.append({"id": f"settings.{page_id}.{section_index}.{item_index}",
                             "label": props["title"], "page": page_id,
                             "icon": props.get("icon") or page.get("icon", ""),
                             "keywords": [title, section_title, props.get("description", ""), "settings"],
                             "context": title})
    return rows


if __name__ == "__main__":
    json.dump(build_catalog(), sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")
