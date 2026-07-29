"""GTK-free PipeWire/PulseAudio querying, controls, and automation policy."""
from __future__ import annotations

import dataclasses
import json
import logging
import os
import shutil
import subprocess
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


log = logging.getLogger(__name__)

CONFIG_DIR = Path.home() / ".config" / "cloud-center"
AUTO_SWITCH_FILE = CONFIG_DIR / "auto_switch.json"
AUTO_SWITCH_DEFAULTS = {
    "enabled": False,
    "output_priority": [],
    "output_priority_labels": {},
    "bluetooth_auto_switch": True,
}


@dataclass
class PortInfo:
    name: str
    description: str
    available: str


@dataclass
class Sink:
    index: int
    name: str
    description: str
    volume: int
    muted: bool
    is_default: bool
    active_port: str
    ports: list[PortInfo] = field(default_factory=list)
    sample_spec: str = ""
    driver: str = ""
    state: str = ""
    properties: dict[str, str] = field(default_factory=dict)


@dataclass
class Source:
    index: int
    name: str
    description: str
    volume: int
    muted: bool
    is_default: bool
    active_port: str
    ports: list[PortInfo] = field(default_factory=list)
    sample_spec: str = ""
    driver: str = ""
    state: str = ""
    properties: dict[str, str] = field(default_factory=dict)


@dataclass
class Stream:
    index: int
    app_name: str
    media_name: str
    sink_name: str
    volume: int
    muted: bool


@dataclass
class Card:
    index: int
    name: str
    driver: str
    active_profile: str
    profiles: list[str]
    profile_descriptions: dict[str, str] = field(default_factory=dict)


def load_auto_switch_config(path: Path = AUTO_SWITCH_FILE) -> dict[str, Any]:
    if not path.exists():
        return dict(AUTO_SWITCH_DEFAULTS)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return {**AUTO_SWITCH_DEFAULTS, **data}
    except (OSError, json.JSONDecodeError, TypeError) as exc:
        log.warning("Failed to load auto-switch config: %s", exc)
    return dict(AUTO_SWITCH_DEFAULTS)


def save_auto_switch_config(
    config: dict[str, Any], path: Path = AUTO_SWITCH_FILE,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".auto_switch.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(config, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        Path(temporary).replace(path)
    except Exception:
        Path(temporary).unlink(missing_ok=True)
        raise


def _run_cmd(
    args: list[str], timeout: int = 8, stderr_to_stdout: bool = False,
) -> tuple[bool, str]:
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        output = ((result.stdout or "") + (result.stderr or "")
                  if stderr_to_stdout else (result.stdout or ""))
        return result.returncode == 0, output
    except Exception as exc:
        return False, str(exc)


def _have_tool(name: str) -> bool:
    return shutil.which(name) is not None


def _pactl_json(section: str) -> list[dict[str, Any]]:
    ok, out = _run_cmd(["pactl", "-f", "json", "list", section], timeout=10)
    if not ok or not out.strip():
        log.warning("pactl -f json list %s failed or empty output", section)
        return []
    try:
        data = json.loads(out)
        candidates: list[str] = {
            "sinks": ["sinks", "sink"],
            "sources": ["sources", "source"],
            "sink-inputs": ["sink-inputs", "sink_inputs"],
            "cards": ["cards", "card"],
        }.get(section, [section])
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            for key in [section] + candidates:
                if key in data and isinstance(data[key], list):
                    return data[key]
            for value in data.values():
                if isinstance(value, list) and value:
                    return value
        log.warning("No list found in pactl %s output", section)
    except json.JSONDecodeError as exc:
        log.error("JSON decode error for pactl list %s: %s", section, exc)
    return []


def _parse_pactl_plaintext(section: str) -> list[dict[str, Any]]:
    ok, out = _run_cmd(["pactl", "list", section])
    if not ok or not out:
        return []
    entries: list[dict[str, Any]] = []
    current: dict[str, Any] = {}
    singular = section.rstrip("s").capitalize()
    for line in out.splitlines():
        line = line.rstrip()
        if line.startswith(singular + " #"):
            if current:
                entries.append(current)
            current = {}
            try:
                current["index"] = int(line.split("#")[1].split()[0])
            except (ValueError, IndexError):
                pass
        elif line.startswith("\t") and ":" in line:
            key, _, value = line.partition(":")
            current[key.strip().lower().replace(" ", "_")] = value.strip()
    if current:
        entries.append(current)
    return entries


def get_default(kind: str) -> str:
    ok, out = _run_cmd(["pactl", f"get-default-{kind}"])
    return out.strip() if ok else ""


def _bluez_device_name(device_name: str) -> str:
    """Resolve a friendly alias for a BlueZ PipeWire device."""
    if not shutil.which("bluetoothctl"):
        return ""
    mac_part = device_name
    for prefix in ("bluez_output.", "bluez_input.", "bluez_source."):
        if mac_part.startswith(prefix):
            mac_part = mac_part[len(prefix):]
            break
    segments = mac_part.split(".")
    if len(segments) >= 2:
        mac_part = ".".join(segments[:-1])
    mac = mac_part.replace("_", ":")
    if len(mac) != 17:
        return ""
    ok, out = _run_cmd(["bluetoothctl", "info", mac], timeout=3)
    if not ok or not out:
        return ""
    for line in out.splitlines():
        stripped = line.strip()
        if stripped.startswith("Alias:"):
            return stripped[len("Alias:"):].strip()
        if stripped.startswith("Name:"):
            return stripped[len("Name:"):].strip()
    return ""


def _norm_vol(value: Any) -> int:
    if isinstance(value, dict):
        percents: list[int] = []
        for channel in value.values():
            if isinstance(channel, dict):
                percent = channel.get("value_percent", "")
                if isinstance(percent, str) and percent.endswith("%"):
                    try:
                        percents.append(int(float(percent[:-1])))
                    except ValueError:
                        pass
        if percents:
            return max(0, min(150, int(sum(percents) / len(percents))))
    return 0


def _extract_ports(entry: dict[str, Any]) -> list[PortInfo]:
    ports_raw = entry.get("ports", [])
    if not isinstance(ports_raw, list):
        return []
    result = []
    for port in ports_raw:
        if isinstance(port, dict):
            result.append(PortInfo(
                name=str(port.get("name", "")),
                description=str(port.get("description", "")),
                available=str(port.get("availability", "unknown")),
            ))
    return result


def list_sinks() -> list[Sink]:
    default_name = get_default("sink")
    sinks: list[Sink] = []
    entries = _pactl_json("sinks") or _parse_pactl_plaintext("sinks")
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        name = str(entry.get("name", ""))
        if not name:
            continue
        raw_desc = str(entry.get("description", ""))
        null_desc = not raw_desc or raw_desc.lower() in ("(null)", "null")
        if null_desc:
            if name.startswith("bluez_"):
                desc = _bluez_device_name(name) or "Bluetooth Audio Device"
                log.debug("Resolved BT sink %s -> %r", name, desc)
            else:
                log.debug("Skipping non-BT sink with null description: %s", name)
                continue
        else:
            desc = raw_desc
        props = entry.get("properties", {})
        if not isinstance(props, dict):
            props = {}
        sinks.append(Sink(
            index=int(entry.get("index", -1)), name=name, description=desc,
            volume=_norm_vol(entry.get("volume", {})), muted=bool(entry.get("mute", False)),
            is_default=name == default_name, active_port=str(entry.get("active_port", "")),
            ports=_extract_ports(entry), sample_spec=str(entry.get("sample_specification", "")),
            driver=str(entry.get("driver", "")), state=str(entry.get("state", "")),
            properties={key: str(value) for key, value in props.items()},
        ))
    sinks.sort(key=lambda sink: (not sink.is_default, sink.description.lower()))
    log.info("Discovered %d sinks", len(sinks))
    return sinks


def list_sources() -> list[Source]:
    default_name = get_default("source")
    sources: list[Source] = []
    entries = _pactl_json("sources") or _parse_pactl_plaintext("sources")
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        name = str(entry.get("name", ""))
        if not name or name.endswith(".monitor"):
            continue
        raw_desc = str(entry.get("description", ""))
        null_desc = not raw_desc or raw_desc.lower() in ("(null)", "null")
        if null_desc:
            if name.startswith("bluez_"):
                desc = _bluez_device_name(name) or "Bluetooth Input Device"
                log.debug("Resolved BT source %s -> %r", name, desc)
            else:
                log.debug("Skipping non-BT source with null description: %s", name)
                continue
        else:
            desc = raw_desc
        props = entry.get("properties", {})
        if not isinstance(props, dict):
            props = {}
        sources.append(Source(
            index=int(entry.get("index", -1)), name=name, description=desc,
            volume=_norm_vol(entry.get("volume", {})), muted=bool(entry.get("mute", False)),
            is_default=name == default_name, active_port=str(entry.get("active_port", "")),
            ports=_extract_ports(entry), sample_spec=str(entry.get("sample_specification", "")),
            driver=str(entry.get("driver", "")), state=str(entry.get("state", "")),
            properties={key: str(value) for key, value in props.items()},
        ))
    sources.sort(key=lambda source: (not source.is_default, source.description.lower()))
    log.info("Discovered %d sources", len(sources))
    return sources


def list_streams() -> list[Stream]:
    streams: list[Stream] = []
    sink_by_index: dict[int, str] = {}
    for sink_entry in _pactl_json("sinks") or []:
        if not isinstance(sink_entry, dict):
            continue
        sink_name = str(sink_entry.get("name", ""))
        if not sink_name:
            continue
        try:
            sink_by_index[int(sink_entry.get("index", -1))] = sink_name
        except (TypeError, ValueError):
            continue
    for entry in _pactl_json("sink-inputs"):
        if not isinstance(entry, dict):
            continue
        props = entry.get("properties", {})
        if not isinstance(props, dict):
            props = {}
        raw_sink = entry.get("sink", "")
        sink_name = str(raw_sink)
        try:
            sink_index = int(raw_sink)
        except (TypeError, ValueError):
            sink_index = None
        if sink_index is not None:
            sink_name = sink_by_index.get(sink_index, sink_name)
        streams.append(Stream(
            index=int(entry.get("index", -1)),
            app_name=str(props.get("application.name", "Unknown App")),
            media_name=str(props.get("media.name", "Playback Stream")),
            sink_name=sink_name,
            volume=_norm_vol(entry.get("volume", {})), muted=bool(entry.get("mute", False)),
        ))
    streams.sort(key=lambda stream: stream.app_name.lower())
    log.info("Discovered %d streams", len(streams))
    return streams


def list_cards() -> list[Card]:
    cards: list[Card] = []
    entries = _pactl_json("cards") or _parse_pactl_plaintext("cards")
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        name = str(entry.get("name", ""))
        if not name:
            continue
        profiles: list[str] = []
        profile_descriptions: dict[str, str] = {}
        profiles_obj = entry.get("profiles", {})
        if isinstance(profiles_obj, dict):
            # pactl -f json: {"profile-name": {"description": "...", ...}, ...}
            for profile_name, meta in profiles_obj.items():
                profile_key = str(profile_name)
                if not profile_key:
                    continue
                profiles.append(profile_key)
                if isinstance(meta, dict):
                    profile_descriptions[profile_key] = str(meta.get("description", profile_key))
                else:
                    profile_descriptions[profile_key] = profile_key
        elif isinstance(profiles_obj, list):
            # plaintext / legacy list shape: [{"name": "...", "description": "..."}, ...]
            for profile in profiles_obj:
                if isinstance(profile, dict):
                    profile_key = str(profile.get("name", ""))
                    if profile_key:
                        profiles.append(profile_key)
                        profile_descriptions[profile_key] = str(profile.get("description", profile_key))
        cards.append(Card(
            index=int(entry.get("index", -1)), name=name,
            driver=str(entry.get("driver", "")), active_profile=str(entry.get("active_profile", "")),
            profiles=profiles, profile_descriptions=profile_descriptions,
        ))
    cards.sort(key=lambda card: card.name.lower())
    log.info("Discovered %d cards", len(cards))
    return cards


def set_sink_volume(name: str, value: int) -> tuple[bool, str]:
    return _run_cmd(["pactl", "set-sink-volume", name, f"{value}%"])


def set_source_volume(name: str, value: int) -> tuple[bool, str]:
    return _run_cmd(["pactl", "set-source-volume", name, f"{value}%"])


def set_stream_volume(stream_id: int, value: int) -> tuple[bool, str]:
    return _run_cmd(["pactl", "set-sink-input-volume", str(stream_id), f"{value}%"])


def set_sink_mute(name: str, mute: bool) -> tuple[bool, str]:
    return _run_cmd(["pactl", "set-sink-mute", name, "1" if mute else "0"])


def set_source_mute(name: str, mute: bool) -> tuple[bool, str]:
    return _run_cmd(["pactl", "set-source-mute", name, "1" if mute else "0"])


def set_stream_mute(stream_id: int, mute: bool) -> tuple[bool, str]:
    return _run_cmd(["pactl", "set-sink-input-mute", str(stream_id), "1" if mute else "0"])


def set_default_sink(name: str) -> tuple[bool, str]:
    return _run_cmd(["pactl", "set-default-sink", name])


def set_default_source(name: str) -> tuple[bool, str]:
    return _run_cmd(["pactl", "set-default-source", name])


def move_stream(stream_id: int, sink_name: str) -> tuple[bool, str]:
    return _run_cmd(["pactl", "move-sink-input", str(stream_id), sink_name])


def set_card_profile(card_name: str, profile_name: str) -> tuple[bool, str]:
    return _run_cmd(["pactl", "set-card-profile", card_name, profile_name])


def set_sink_port(sink_name: str, port_name: str) -> tuple[bool, str]:
    return _run_cmd(["pactl", "set-sink-port", sink_name, port_name])


def set_source_port(source_name: str, port_name: str) -> tuple[bool, str]:
    return _run_cmd(["pactl", "set-source-port", source_name, port_name])


def is_bluetooth_sink(name: str) -> bool:
    return name.startswith("bluez_")


def migrate_all_streams_to_sink(sink_name: str) -> tuple[bool, str]:
    streams = list_streams()
    if not streams:
        return True, ""
    errors: list[str] = []
    for stream in streams:
        ok, error = move_stream(stream.index, sink_name)
        if not ok:
            errors.append(error.strip() or f"stream {stream.index}")
    return (False, "; ".join(errors)) if errors else (True, "")


def switch_output(sink_name: str) -> tuple[bool, str]:
    ok, error = set_default_sink(sink_name)
    if not ok:
        return ok, error
    moved_ok, move_error = migrate_all_streams_to_sink(sink_name)
    return (False, move_error) if not moved_ok else (True, "")


def device_type(name: str, properties: dict[str, str]) -> str:
    bus = properties.get("device.bus", "").lower()
    if name.startswith("bluez_") or bus == "bluetooth":
        return "Bluetooth"
    if bus == "usb" or ".usb-" in name:
        return "USB"
    return "Built-in"


def resolve_output_priority_labels(
    priority: list[str],
    sinks: list[Sink] | None = None,
    existing: dict[str, Any] | None = None,
) -> dict[str, str]:
    """Friendly names for priority rows, including offline remembered sinks."""
    live = {sink.name: sink.description for sink in (sinks if sinks is not None else list_sinks())}
    previous = {
        str(name): str(label)
        for name, label in (existing or {}).items()
        if isinstance(name, str) and isinstance(label, str) and name and label
    }
    labels: dict[str, str] = {}
    for name in priority:
        if not isinstance(name, str) or not name:
            continue
        if name in live and live[name]:
            labels[name] = live[name]
            continue
        if name in previous:
            labels[name] = previous[name]
            continue
        if name.startswith("bluez_"):
            alias = _bluez_device_name(name)
            if alias:
                labels[name] = alias
    return labels


def serialize_device(item: Sink | Source) -> dict[str, Any]:
    result = dataclasses.asdict(item)
    result["type"] = device_type(item.name, item.properties)
    return result


def build_audio_snapshot(service: dict[str, Any] | None = None) -> dict[str, Any]:
    sinks = list_sinks()
    config = load_auto_switch_config()
    priority = list(config.get("output_priority", []))
    existing = config.get("output_priority_labels", {})
    if not isinstance(existing, dict):
        existing = {}
    labels = resolve_output_priority_labels(priority, sinks=sinks, existing=existing)
    # Persist newly resolved labels so offline rows keep friendly names later.
    if labels != existing:
        config["output_priority_labels"] = labels
        save_auto_switch_config(config)
    automation = dict(config)
    automation["output_priority_labels"] = labels
    return {
        "sinks": [serialize_device(item) for item in sinks],
        "sources": [serialize_device(item) for item in list_sources()],
        "streams": [dataclasses.asdict(item) for item in list_streams()],
        "cards": [dataclasses.asdict(item) for item in list_cards()],
        "automation": automation,
        "service": service or {},
    }


def execute_audio_action(action: str, target: str, value: Any) -> tuple[bool, str]:
    volume = lambda raw: max(0, min(150, int(round(float(raw)))))
    actions = {
        "set_sink_volume": lambda: set_sink_volume(target, volume(value)),
        "set_source_volume": lambda: set_source_volume(target, volume(value)),
        "set_stream_volume": lambda: set_stream_volume(int(target), volume(value)),
        "set_sink_mute": lambda: set_sink_mute(target, bool(value)),
        "set_source_mute": lambda: set_source_mute(target, bool(value)),
        "set_stream_mute": lambda: set_stream_mute(int(target), bool(value)),
        "set_default_sink": lambda: switch_output(target),
        "set_default_source": lambda: set_default_source(target),
        "move_stream": lambda: move_stream(int(target), str(value)),
        "set_sink_port": lambda: set_sink_port(target, str(value)),
        "set_source_port": lambda: set_source_port(target, str(value)),
        "set_card_profile": lambda: set_card_profile(target, str(value)),
    }
    try:
        operation = actions[action]
    except KeyError as exc:
        raise ValueError(f"unknown audio action: {action}") from exc
    return operation()


class AutoSwitchPolicy:
    def __init__(self) -> None:
        self.known_bt_sinks: set[str] = set()
        self.bt_activity: dict[str, float] = {}
        self.bootstrapped = False

    def pick_bluetooth_sink(
        self, sinks: list[Sink], now: float | None = None,
    ) -> str | None:
        bt_sinks = [sink for sink in sinks if is_bluetooth_sink(sink.name)]
        if not bt_sinks:
            return None
        current_bt = {sink.name for sink in bt_sinks}
        if not self.bootstrapped:
            self.known_bt_sinks = set(current_bt)
            self.bootstrapped = True
            return None
        new_bt = current_bt - self.known_bt_sinks
        self.known_bt_sinks = current_bt
        timestamp = time.monotonic() if now is None else now
        for sink in bt_sinks:
            if sink.state.upper() == "RUNNING":
                self.bt_activity[sink.name] = timestamp
        if new_bt:
            return sorted(new_bt)[-1]
        active = [sink for sink in bt_sinks if sink.state.upper() in ("RUNNING", "IDLE")]
        if not active:
            return None
        running = [sink for sink in active if sink.state.upper() == "RUNNING"]
        candidates = running or active
        return max(candidates, key=lambda sink: self.bt_activity.get(sink.name, 0.0)).name

    def pick_priority_sink(self, sinks: list[Sink], priority: list[str]) -> str | None:
        sink_by_name = {sink.name: sink for sink in sinks}
        for state in ("RUNNING", "IDLE"):
            for name in priority:
                sink = sink_by_name.get(name)
                if sink and sink.state.upper() == state:
                    return name
        return None

    def choose(
        self, sinks: list[Sink], current_default: str,
        config: dict[str, Any], now: float | None = None,
    ) -> str | None:
        best = None
        if bool(config.get("bluetooth_auto_switch", True)):
            best = self.pick_bluetooth_sink(sinks, now)
        if best is None and bool(config.get("enabled", False)):
            best = self.pick_priority_sink(sinks, list(config.get("output_priority", [])))
        return best if best and best != current_default else None
