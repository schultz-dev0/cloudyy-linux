from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ModulePaths:
    surface: str
    source_module: str
    source_comment: str
    user_module: str
    user_comment: str


def module_paths(surface: str) -> ModulePaths:
    user_module = f'require("user-configs.user_{surface}") -- managed by Cloud Center'
    return ModulePaths(
        surface=surface,
        source_module=f'require("source.{surface}")',
        source_comment=f'-- require("source.{surface}")',
        user_module=user_module,
        user_comment=f"-- {user_module}",
    )


def ensure_user_override_active(text: str, surface: str) -> str:
    paths = module_paths(surface)
    lines = []
    has_active_user_module = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == paths.source_module:
            lines.append(paths.source_comment)
        elif stripped in {paths.user_module, paths.user_comment}:
            if not has_active_user_module:
                lines.append(paths.user_module)
                has_active_user_module = True
        else:
            lines.append(line)
    updated = "\n".join(lines)
    if not has_active_user_module:
        if updated.endswith("\n"):
            updated = updated + paths.user_module + "\n"
        else:
            updated = updated + "\n" + paths.user_module + "\n"
    elif not updated.endswith("\n"):
        updated = updated + "\n"
    return updated


def ensure_source_active(text: str, surface: str) -> str:
    paths = module_paths(surface)
    lines = []
    has_inactive_user_module = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == paths.source_comment:
            lines.append(paths.source_module)
        elif stripped in {paths.user_module, paths.user_comment}:
            if not has_inactive_user_module:
                lines.append(paths.user_comment)
                has_inactive_user_module = True
        else:
            lines.append(line)
    updated = "\n".join(lines)
    return updated + ("\n" if updated else "")


SIDECAR_CONFS = {"hypridle.conf", "hyprlock.conf", "xdph.conf"}
_ARCHIVE_SENTINEL = ".archived"


def archive_legacy_conf_tree(hypr_dir: Path) -> None:
    legacy_dir = hypr_dir / ".legacy"
    if (legacy_dir / _ARCHIVE_SENTINEL).exists():
        print("[hypr_persist] legacy conf archive already complete, skipping")
        return

    legacy_dir.mkdir(parents=True, exist_ok=True)
    archived = 0

    for path in hypr_dir.glob("*.conf"):
        if path.name in SIDECAR_CONFS:
            continue
        path.replace(legacy_dir / path.name)
        archived += 1

    for rel_dir in ("source", "user-configs"):
        base = hypr_dir / rel_dir
        if not base.exists():
            continue
        for path in base.glob("*.conf"):
            target_parent = legacy_dir / rel_dir
            target_parent.mkdir(parents=True, exist_ok=True)
            path.replace(target_parent / path.name)
            archived += 1

    (legacy_dir / _ARCHIVE_SENTINEL).write_text("", encoding="utf-8")
    print(f"[hypr_persist] archived {archived} legacy .conf file(s) -> {legacy_dir}")
