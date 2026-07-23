"""GTK-free bezier curve store/math/apply for Cloud Center."""
from __future__ import annotations

import json
import logging
import subprocess
from pathlib import Path
from typing import Any

import lib.utility as utility

log = logging.getLogger(__name__)

CURVES_PATH = Path.home() / ".config" / "cloud-center" / "bezier_curves.json"

BUILTIN_PRESETS: dict[str, tuple[float, float, float, float]] = {
    "ease": (0.25, 0.10, 0.25, 1.00),
    "easeIn": (0.42, 0.00, 1.00, 1.00),
    "easeOut": (0.00, 0.00, 0.58, 1.00),
    "easeInOut": (0.42, 0.00, 0.58, 1.00),
    "easeOutBack": (0.34, 1.56, 0.64, 1.00),
    "easeInOutBack": (0.68, -0.60, 0.32, 1.60),
    "easeOutExpo": (0.16, 1.00, 0.30, 1.00),
    "easeOutCubic": (0.33, 1.00, 0.68, 1.00),
    "easeOutQuad": (0.50, 1.00, 0.89, 1.00),
    "easeInOutSine": (0.37, 0.00, 0.63, 1.00),
    "linear": (0.00, 0.00, 1.00, 1.00),
}

# Newbie-facing chips → builtin preset ids
FEEL_CHIPS: list[dict[str, str]] = [
    {"id": "linear", "label": "Linear"},
    {"id": "easeOutCubic", "label": "Smooth"},
    {"id": "easeOutExpo", "label": "Snappy"},
    {"id": "easeOutBack", "label": "Bouncy"},
]


def _cubic(t: float, p1: float, p2: float) -> float:
    return 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3


def _solve_t(x: float, x1: float, x2: float, eps: float = 1e-6) -> float:
    t = x
    for _ in range(20):
        fx = _cubic(t, x1, x2)
        dx = 3 * (1 - t) ** 2 * x1 + 6 * (1 - t) * t * (x2 - x1) + 3 * t ** 2 * (1 - x2)
        if abs(dx) < eps:
            break
        t -= (fx - x) / dx
        t = max(0.0, min(1.0, t))
    return t


def ease(p: float, x1: float, y1: float, x2: float, y2: float) -> float:
    return _cubic(_solve_t(p, x1, x2), y1, y2)


def sample_curve(
    x1: float, y1: float, x2: float, y2: float, *, steps: int = 48,
) -> list[dict[str, float]]:
    points: list[dict[str, float]] = []
    for i in range(steps + 1):
        t = i / steps
        points.append({"x": t, "y": ease(t, x1, y1, x2, y2)})
    return points


class CurveStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or CURVES_PATH
        self._user: dict[str, tuple[float, float, float, float]] = {}
        self.reload()

    def reload(self) -> None:
        if not self.path.exists():
            self._user = {}
            return
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            self._user = {k: tuple(float(n) for n in v) for k, v in raw.items()}  # type: ignore[misc]
        except Exception:
            self._user = {}

    def _save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(
            json.dumps({k: list(v) for k, v in self._user.items()}, indent=2),
            encoding="utf-8",
        )

    def all_names(self) -> list[str]:
        return list(BUILTIN_PRESETS) + list(self._user)

    def user_names(self) -> list[str]:
        return list(self._user)

    def is_builtin(self, name: str) -> bool:
        return name in BUILTIN_PRESETS

    def get_points(self, name: str) -> tuple[float, float, float, float] | None:
        if name in BUILTIN_PRESETS:
            return BUILTIN_PRESETS[name]
        return self._user.get(name)

    def save(self, name: str, pts: tuple[float, float, float, float]) -> None:
        self._user[name] = pts
        self._save()

    def delete(self, name: str) -> None:
        self._user.pop(name, None)
        self._save()

    def next_name(self) -> str:
        i = 1
        while f"myBezier{i}" in self._user or f"myBezier{i}" in BUILTIN_PRESETS:
            i += 1
        return f"myBezier{i}"


def _pts_list(pts: tuple[float, float, float, float]) -> list[float]:
    return [round(float(v), 3) for v in pts]


def list_curves(store: CurveStore | None = None) -> dict[str, Any]:
    store = store or CurveStore()
    curves = []
    for name in store.all_names():
        pts = store.get_points(name)
        if pts is None:
            continue
        curves.append({
            "id": name,
            "name": name,
            "points": _pts_list(pts),
            "builtin": store.is_builtin(name),
            "samples": sample_curve(*pts, steps=24),
        })
    return {
        "curves": curves,
        "chips": list(FEEL_CHIPS),
        "next_name": store.next_name(),
        "default_id": "easeOutCubic",
        "error": "",
    }


def save_curve(
    name: str,
    points: list[float] | tuple[float, float, float, float],
    *,
    store: CurveStore | None = None,
) -> dict[str, Any]:
    store = store or CurveStore()
    cleaned = str(name or "").strip()
    if not cleaned:
        raise ValueError("curve name is required")
    if store.is_builtin(cleaned):
        raise ValueError("cannot overwrite a built-in preset; pick a new name")
    if len(points) != 4:
        raise ValueError("points must be [x1, y1, x2, y2]")
    pts = tuple(float(v) for v in points)
    if not (0.0 <= pts[0] <= 1.0 and 0.0 <= pts[2] <= 1.0):
        raise ValueError("x1 and x2 must be between 0 and 1")
    store.save(cleaned, pts)  # type: ignore[arg-type]
    return {
        "ok": True,
        "name": cleaned,
        "points": _pts_list(pts),  # type: ignore[arg-type]
        "message": f'Saved curve "{cleaned}"',
    }


def delete_curve(name: str, *, store: CurveStore | None = None) -> dict[str, Any]:
    store = store or CurveStore()
    cleaned = str(name or "").strip()
    if not cleaned:
        raise ValueError("curve name is required")
    if store.is_builtin(cleaned):
        raise ValueError("cannot delete a built-in preset")
    if cleaned not in store.user_names():
        raise ValueError(f'unknown curve "{cleaned}"')
    store.delete(cleaned)
    return {"ok": True, "name": cleaned, "message": f'Deleted "{cleaned}"'}


def apply_curve(
    name: str,
    points: list[float] | tuple[float, float, float, float],
    *,
    store: CurveStore | None = None,
    save_if_custom: bool = True,
) -> dict[str, Any]:
    store = store or CurveStore()
    cleaned = str(name or "").strip() or "cloudCenterBezier"
    if len(points) != 4:
        raise ValueError("points must be [x1, y1, x2, y2]")
    pts = tuple(float(v) for v in points)
    if save_if_custom and not store.is_builtin(cleaned):
        store.save(cleaned, pts)  # type: ignore[arg-type]

    bezier_str = f"{cleaned},{pts[0]},{pts[1]},{pts[2]},{pts[3]}"
    from lib import hypr_anim

    speed = hypr_anim.hypr_speed_from_setting()
    anim_value = hypr_anim.upsert_windows_leaf(speed=speed, bezier=cleaned)

    for key, value in (
        ("animations:bezier", bezier_str),
        ("animations:animation", anim_value),
    ):
        try:
            run = subprocess.run(
                ["hcm", "apply", key, value],
                capture_output=True, text=True, timeout=5,
            )
        except Exception as exc:
            return {"ok": False, "message": f"Apply failed: {exc}"}
        if run.returncode != 0:
            err = (run.stderr or run.stdout or "hcm apply failed").strip()
            return {"ok": False, "message": f"Apply failed: {err}"}

    return {
        "ok": True,
        "name": cleaned,
        "points": _pts_list(pts),  # type: ignore[arg-type]
        "message": f'Applied "{cleaned}" to Hyprland windows animation',
    }
