"""GTK-free ccd protocol adapter for the Bezier curve editor."""
from __future__ import annotations

from typing import Any

from lib import bezier_core
from lib.ccd import protocol


def _points_from(params: dict[str, Any]) -> list[float]:
    raw = params.get("points")
    if not isinstance(raw, (list, tuple)) or len(raw) != 4:
        raise ValueError("points must be [x1, y1, x2, y2]")
    try:
        return [float(v) for v in raw]
    except (TypeError, ValueError) as exc:
        raise ValueError("points must be numbers") from exc


def list_bezier_curves(_params: dict[str, Any]) -> dict[str, Any]:
    return bezier_core.list_curves()


def save_bezier_curve(params: dict[str, Any]) -> dict[str, Any]:
    name = params.get("name")
    if not isinstance(name, str):
        raise ValueError("name must be a string")
    return bezier_core.save_curve(name, _points_from(params))


def delete_bezier_curve(params: dict[str, Any]) -> dict[str, Any]:
    name = params.get("name")
    if not isinstance(name, str) or not name.strip():
        raise ValueError("name must be a non-empty string")
    return bezier_core.delete_curve(name.strip())


def apply_bezier_curve(params: dict[str, Any]) -> dict[str, Any]:
    name = params.get("name", "cloudCenterBezier")
    if not isinstance(name, str):
        raise ValueError("name must be a string")
    return bezier_core.apply_curve(name, _points_from(params))


protocol.register("list_bezier_curves", list_bezier_curves)
protocol.register("save_bezier_curve", save_bezier_curve)
protocol.register("delete_bezier_curve", delete_bezier_curve)
protocol.register("apply_bezier_curve", apply_bezier_curve)
