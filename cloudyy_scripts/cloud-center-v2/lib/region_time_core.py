"""GTK-free Region & Time snapshot/actions for Cloud Center."""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo

import lib.datetime_helpers as dt
import lib.geoclue_helpers as geo
import lib.offline_geocode as offline_geocode
import lib.utility as utility

log = logging.getLogger(__name__)

ALLOWED_ACTIONS = frozenset({
    "set_ntp",
    "set_timezone",
    "set_time",
    "set_manual_mode",
    "apply_location",
    "clear_location",
})


def _location_dict(loc: geo.GeoLocation | None) -> dict[str, Any] | None:
    if loc is None:
        return None
    return {
        "latitude": loc.latitude,
        "longitude": loc.longitude,
        "accuracy": loc.accuracy,
        "altitude": loc.altitude,
        "source": loc.source,
        "place_name": loc.place_name,
        "formatted": geo.format_location(loc),
    }


def timezone_offsets(zones: list[str] | None = None) -> dict[str, str]:
    zones = zones if zones is not None else dt.list_timezones()
    now_utc = datetime.now(timezone.utc)
    offsets: dict[str, str] = {}
    for tz in zones:
        try:
            tz_info = ZoneInfo(tz)
            off = now_utc.astimezone(tz_info).utcoffset()
            if off is None:
                offsets[tz] = ""
                continue
            total = int(off.total_seconds() // 60)
            sign = "+" if total >= 0 else "-"
            abs_m = abs(total)
            offsets[tz] = f"UTC{sign}{abs_m // 60:02d}:{abs_m % 60:02d}"
        except Exception:
            offsets[tz] = ""
    return offsets


def build_region_snapshot(*, include_location: bool = True) -> dict[str, Any]:
    status_text = dt.get_status_text()
    timezone_name = dt.get_timezone()
    ntp_enabled = dt.get_ntp_enabled()
    polkit_ready = dt.ensure_polkit_agent()
    manual = geo.is_manual_mode()
    saved_mode = utility.load_setting("region/location_mode", "auto")
    saved_lat = utility.load_setting("region/manual_lat", "")
    saved_lon = utility.load_setting("region/manual_lon", "")
    static = geo.read_static_geolocation()
    location = None
    if include_location:
        try:
            location = geo.get_location()
        except Exception as exc:
            log.debug("location lookup failed: %s", exc)
            location = static

    try:
        now = datetime.now(ZoneInfo(timezone_name)) if timezone_name else datetime.now()
    except Exception:
        now = datetime.now()

    return {
        "polkit_ready": polkit_ready,
        "polkit_message": (
            "Ready — hyprpolkitagent will prompt for your password"
            if polkit_ready
            else "Starting polkit agent… privileged actions disabled until ready"
        ),
        "offline_places_available": offline_geocode.data_available(),
        "offline_places_message": (
            "GeoNames cities database loaded (no network needed)"
            if offline_geocode.data_available()
            else "Missing — run: bash ~/cloudyy-linux/install/setup-region-time.sh"
        ),
        "timezone": timezone_name,
        "timezone_label": status_text.get("timezone", timezone_name) or timezone_name or "—",
        "local_clock": dt.format_local_clock(timezone_name),
        "ntp_enabled": ntp_enabled,
        "ntp_sync": status_text.get("ntp_sync", "unknown"),
        "ntp_service": status_text.get("ntp_service", "unknown"),
        "ntp_status_label": (
            f"Synchronized: {status_text.get('ntp_sync', 'unknown')}  ·  "
            f"NTP: {status_text.get('ntp_service', 'unknown')}"
        ),
        "geo_active": geo.service_active(),
        "geo_service_label": (
            "Running" if geo.service_active()
            else "Not running — install/start geoclue"
        ),
        "manual_location": manual or saved_mode == "manual",
        "saved_mode": saved_mode,
        "saved_lat": saved_lat,
        "saved_lon": saved_lon,
        "static_location": _location_dict(static),
        "location": _location_dict(location),
        "location_label": geo.format_location(location),
        "clock": {
            "year": now.year,
            "month": now.month,
            "day": now.day,
            "hour": now.hour,
            "minute": now.minute,
            "second": now.second,
        },
        "error": "",
    }


def list_timezones_payload() -> dict[str, Any]:
    zones = dt.list_timezones()
    offsets = timezone_offsets(zones)
    return {
        "timezones": [
            {"id": tz, "label": tz, "offset": offsets.get(tz, "")}
            for tz in zones
        ],
    }


def run_region_action(action: str, value: Any = None) -> dict[str, Any]:
    if action not in ALLOWED_ACTIONS:
        raise ValueError(f"unknown region action: {action}")

    needs_polkit = action in (
        "set_ntp", "set_timezone", "set_time", "apply_location", "clear_location",
    ) or (action == "set_manual_mode" and value is False)
    if needs_polkit and not dt.ensure_polkit_agent():
        return {"ok": False, "message": dt.NO_POLKIT_AGENT_MSG}

    if action == "set_ntp":
        if not isinstance(value, bool):
            raise ValueError("ntp value must be a boolean")
        ok, msg = dt.set_ntp(value)
        return {
            "ok": ok,
            "message": (
                f"NTP {'enabled' if value else 'disabled'}" if ok
                else f"NTP change failed: {msg}"
            ),
        }

    if action == "set_timezone":
        if not isinstance(value, str) or not value.strip():
            raise ValueError("timezone must be a non-empty string")
        tz = value.strip()
        ok, msg = dt.set_timezone(tz)
        return {
            "ok": ok,
            "message": f"Timezone set to {tz}" if ok else f"Timezone change failed: {msg}",
        }

    if action == "set_time":
        if not isinstance(value, dict):
            raise ValueError("time value must be an object")
        try:
            year = int(value["year"])
            month = int(value["month"])
            day = int(value["day"])
            hour = int(value["hour"])
            minute = int(value["minute"])
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError("time requires year, month, day, hour, minute") from exc
        if dt.get_ntp_enabled():
            return {"ok": False, "message": "Disable NTP before setting manual time"}
        tz_name = dt.get_timezone()
        try:
            tz_info = ZoneInfo(tz_name) if tz_name else None
        except Exception:
            tz_info = None
        local_dt = datetime(year, month, day, hour, minute, tzinfo=tz_info)
        ok, msg = dt.set_manual_time(local_dt)
        return {
            "ok": ok,
            "message": "Clock updated" if ok else f"Time change failed: {msg}",
        }

    if action == "set_manual_mode":
        if not isinstance(value, bool):
            raise ValueError("manual mode must be a boolean")
        utility.save_setting("region/location_mode", "manual" if value else "auto")
        if not value:
            ok, msg = geo.clear_manual_location()
            return {
                "ok": ok,
                "message": (
                    "Automatic location restored" if ok
                    else f"Clear failed: {msg}"
                ),
            }
        return {"ok": True, "message": "Manual location mode enabled"}

    if action == "apply_location":
        if not isinstance(value, dict):
            raise ValueError("location value must be an object")
        try:
            lat = float(value["latitude"])
            lon = float(value["longitude"])
            acc = float(value.get("accuracy", 200))
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError("location requires latitude and longitude") from exc
        utility.save_setting("region/manual_lat", str(lat))
        utility.save_setting("region/manual_lon", str(lon))
        ok, msg = geo.apply_manual_location(lat, lon, accuracy=acc)
        if ok:
            utility.save_setting("region/location_mode", "manual")
        return {
            "ok": ok,
            "message": "Static location applied" if ok else f"Location failed: {msg}",
        }

    if action == "clear_location":
        utility.save_setting("region/location_mode", "auto")
        ok, msg = geo.clear_manual_location()
        return {
            "ok": ok,
            "message": (
                "Automatic location restored" if ok else f"Clear failed: {msg}"
            ),
        }

    raise ValueError(f"unknown region action: {action}")
