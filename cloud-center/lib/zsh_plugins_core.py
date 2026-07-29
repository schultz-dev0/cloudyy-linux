"""GTK-free Oh My Zsh plugin list/toggle for Cloud Center."""
from __future__ import annotations

from pathlib import Path
from typing import Any

ACTIVE_ZSH_PLUGINS_FILE = (
    Path.home() / ".config/cloud-center/settings/terminal/active_zsh_plugins.txt"
)
ZSH_PLUGINS_DIR = Path.home() / ".config/zsh/oh-my-zsh/plugins"
CUSTOM_PLUGINS_DIR = Path.home() / ".config/zsh/oh-my-zsh/custom/plugins"
VISIBLE_LIMIT = 100


def active_plugins_path() -> Path:
    return ACTIVE_ZSH_PLUGINS_FILE


def read_active_plugins(path: Path | None = None) -> set[str]:
    target = path or ACTIVE_ZSH_PLUGINS_FILE
    active: set[str] = set()
    if not target.exists():
        return active
    with open(target, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line and not line.startswith("#"):
                active.add(line)
    return active


def write_active_plugins(names: set[str], path: Path | None = None) -> None:
    target = path or ACTIVE_ZSH_PLUGINS_FILE
    target.parent.mkdir(parents=True, exist_ok=True)
    with open(target, "w", encoding="utf-8") as handle:
        for name in sorted(names):
            handle.write(f"{name}\n")


def _readme_description(plugin_dir: Path) -> str:
    readme = plugin_dir / "README.md"
    if not readme.exists():
        return ""
    try:
        with open(readme, encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                line = line.strip()
                if line and not line.startswith("#") and not line.startswith("["):
                    return line[:100] + ("..." if len(line) > 100 else "")
    except OSError:
        return ""
    return ""


def scan_plugins(
    *,
    plugins_dir: Path | None = None,
    custom_dir: Path | None = None,
    active: set[str] | None = None,
) -> list[dict[str, Any]]:
    active = active if active is not None else read_active_plugins()
    found: dict[str, dict[str, Any]] = {}

    def scan_dir(directory: Path) -> None:
        if not directory.exists():
            return
        for entry in directory.iterdir():
            if not entry.is_dir() or entry.name.startswith("."):
                continue
            found[entry.name] = {
                "name": entry.name,
                "desc": _readme_description(entry),
                "enabled": entry.name in active,
            }

    scan_dir(plugins_dir or ZSH_PLUGINS_DIR)
    scan_dir(custom_dir or CUSTOM_PLUGINS_DIR)
    plugins = list(found.values())
    plugins.sort(key=lambda item: (not item["enabled"], item["name"]))
    return plugins


def list_plugins(
    *,
    query: str = "",
    enabled_only: bool = False,
    limit: int = VISIBLE_LIMIT,
    plugins_dir: Path | None = None,
    custom_dir: Path | None = None,
    active_path: Path | None = None,
) -> dict[str, Any]:
    active = read_active_plugins(active_path)
    plugins = scan_plugins(
        plugins_dir=plugins_dir,
        custom_dir=custom_dir,
        active=active,
    )
    needle = query.strip().lower()
    filtered: list[dict[str, Any]] = []
    for plugin in plugins:
        if enabled_only and not plugin["enabled"]:
            continue
        if needle and needle not in plugin["name"].lower() and needle not in plugin["desc"].lower():
            continue
        filtered.append(plugin)
        if limit > 0 and len(filtered) >= limit:
            break
    return {
        "plugins": filtered,
        "total": len(plugins),
        "active_count": sum(1 for plugin in plugins if plugin["enabled"]),
        "truncated": bool(limit > 0 and len(filtered) >= limit),
        "error": "",
    }


def set_plugin_enabled(
    name: str,
    enabled: bool,
    *,
    active_path: Path | None = None,
) -> dict[str, Any]:
    plugin = str(name or "").strip()
    if not plugin:
        raise ValueError("plugin name is required")
    active = read_active_plugins(active_path)
    if enabled:
        active.add(plugin)
    else:
        active.discard(plugin)
    write_active_plugins(active, active_path)
    return {
        "ok": True,
        "name": plugin,
        "enabled": enabled,
        "message": f"{'Enabled' if enabled else 'Disabled'} {plugin}",
    }
