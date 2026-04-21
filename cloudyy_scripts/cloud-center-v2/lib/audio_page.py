"""Cloud Center — Audio manager page backed by PipeWire/PulseAudio tools."""
from __future__ import annotations

import json
import logging
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from gi.repository import Adw, GLib, Gtk

import lib.utility as utility

log = logging.getLogger(__name__)

CONFIG_DIR = Path.home() / ".config" / "cloud-center"
AUTO_SWITCH_FILE = CONFIG_DIR / "auto_switch.json"


# ── Data classes ──────────────────────────────────────────────────────────────

@dataclass
class PortInfo:
    name: str
    description: str
    available: str  # "available" | "not available" | "availability unknown"


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


# ── Auto-switch config helpers ────────────────────────────────────────────────

def load_auto_switch_config() -> dict[str, Any]:
    if not AUTO_SWITCH_FILE.exists():
        return {"enabled": False, "output_priority": []}
    try:
        with open(AUTO_SWITCH_FILE) as f:
            return json.load(f)
    except Exception as e:
        log.warning("Failed to load auto-switch config: %s", e)
        return {"enabled": False, "output_priority": []}


def save_auto_switch_config(cfg: dict[str, Any]) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    try:
        with open(AUTO_SWITCH_FILE, "w") as f:
            json.dump(cfg, f, indent=2)
    except Exception as e:
        log.error("Failed to save auto-switch config: %s", e)


# ── Backend helpers ───────────────────────────────────────────────────────────

def _run_cmd(
    args: list[str], timeout: int = 8, stderr_to_stdout: bool = False
) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        output = (
            (result.stdout or "") + (result.stderr or "")
            if stderr_to_stdout
            else (result.stdout or "")
        )
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
            for v in data.values():
                if isinstance(v, list) and v:
                    return v
        log.warning("No list found in pactl %s output", section)
    except json.JSONDecodeError as e:
        log.error("JSON decode error for pactl list %s: %s", section, e)
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


def _get_default(kind: str) -> str:
    ok, out = _run_cmd(["pactl", f"get-default-{kind}"])
    return out.strip() if ok else ""


def _bluez_device_name(device_name: str) -> str:
    """Resolve friendly alias for a bluez PipeWire device via bluetoothctl."""
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


def _norm_vol(v: Any) -> int:
    if isinstance(v, dict):
        percents: list[int] = []
        for x in v.values():
            if isinstance(x, dict):
                pct_str = x.get("value_percent", "")
                if isinstance(pct_str, str) and pct_str.endswith("%"):
                    try:
                        percents.append(int(float(pct_str[:-1])))
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
    for p in ports_raw:
        if not isinstance(p, dict):
            continue
        result.append(PortInfo(
            name=str(p.get("name", "")),
            description=str(p.get("description", "")),
            available=str(p.get("availability", "unknown")),
        ))
    return result


# ── Device query functions ────────────────────────────────────────────────────

def list_sinks() -> list[Sink]:
    default_name = _get_default("sink")
    sinks: list[Sink] = []
    entries = _pactl_json("sinks")
    if not entries:
        entries = _parse_pactl_plaintext("sinks")

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
                resolved = _bluez_device_name(name)
                desc = resolved or "Bluetooth Audio Device"
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
            index=int(entry.get("index", -1)),
            name=name,
            description=desc,
            volume=_norm_vol(entry.get("volume", {})),
            muted=bool(entry.get("mute", False)),
            is_default=name == default_name,
            active_port=str(entry.get("active_port", "")),
            ports=_extract_ports(entry),
            sample_spec=str(entry.get("sample_specification", "")),
            driver=str(entry.get("driver", "")),
            state=str(entry.get("state", "")),
            properties={k: str(v) for k, v in props.items()},
        ))

    sinks.sort(key=lambda s: (not s.is_default, s.description.lower()))
    log.info("Discovered %d sinks", len(sinks))
    return sinks


def list_sources() -> list[Source]:
    default_name = _get_default("source")
    sources: list[Source] = []
    entries = _pactl_json("sources")
    if not entries:
        entries = _parse_pactl_plaintext("sources")

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
                resolved = _bluez_device_name(name)
                desc = resolved or "Bluetooth Input Device"
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
            index=int(entry.get("index", -1)),
            name=name,
            description=desc,
            volume=_norm_vol(entry.get("volume", {})),
            muted=bool(entry.get("mute", False)),
            is_default=name == default_name,
            active_port=str(entry.get("active_port", "")),
            ports=_extract_ports(entry),
            sample_spec=str(entry.get("sample_specification", "")),
            driver=str(entry.get("driver", "")),
            state=str(entry.get("state", "")),
            properties={k: str(v) for k, v in props.items()},
        ))

    sources.sort(key=lambda s: (not s.is_default, s.description.lower()))
    log.info("Discovered %d sources", len(sources))
    return sources


def list_streams() -> list[Stream]:
    streams: list[Stream] = []
    for entry in _pactl_json("sink-inputs"):
        if not isinstance(entry, dict):
            continue
        props = entry.get("properties", {})
        if not isinstance(props, dict):
            props = {}
        streams.append(Stream(
            index=int(entry.get("index", -1)),
            app_name=str(props.get("application.name", "Unknown App")),
            media_name=str(props.get("media.name", "Playback Stream")),
            sink_name=str(entry.get("sink", "")),
            volume=_norm_vol(entry.get("volume", {})),
            muted=bool(entry.get("mute", False)),
        ))
    streams.sort(key=lambda s: s.app_name.lower())
    log.info("Discovered %d streams", len(streams))
    return streams


def list_cards() -> list[Card]:
    cards: list[Card] = []
    entries = _pactl_json("cards")
    if not entries:
        entries = _parse_pactl_plaintext("cards")

    for entry in entries:
        if not isinstance(entry, dict):
            continue
        name = str(entry.get("name", ""))
        if not name:
            continue
        profiles_obj = entry.get("profiles", [])
        profiles: list[str] = []
        profile_descs: dict[str, str] = {}
        if isinstance(profiles_obj, list):
            for p in profiles_obj:
                if isinstance(p, dict):
                    pn = str(p.get("name", ""))
                    pd = str(p.get("description", pn))
                    if pn:
                        profiles.append(pn)
                        profile_descs[pn] = pd
        cards.append(Card(
            index=int(entry.get("index", -1)),
            name=name,
            driver=str(entry.get("driver", "")),
            active_profile=str(entry.get("active_profile", "")),
            profiles=[p for p in profiles if p],
            profile_descriptions=profile_descs,
        ))
    cards.sort(key=lambda c: c.name.lower())
    log.info("Discovered %d cards", len(cards))
    return cards


# ── Control functions ─────────────────────────────────────────────────────────

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


# ── Auto-switch monitor ───────────────────────────────────────────────────────

class _AutoSwitchMonitor:
    """Background thread: watches pactl subscribe and switches on sink events."""

    def __init__(self, on_switch: Any = None) -> None:
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._on_switch = on_switch

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._thread = threading.Thread(
            target=self._run, daemon=True, name="audio-autoswitch"
        )
        self._thread.start()
        log.debug("Auto-switch monitor started")

    def stop(self) -> None:
        self._stop_event.set()
        log.debug("Auto-switch monitor stop requested")

    def _run(self) -> None:
        try:
            proc = subprocess.Popen(
                ["pactl", "subscribe"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
        except Exception as e:
            log.error("Failed to start pactl subscribe: %s", e)
            return
        last_eval: float = 0.0
        try:
            while not self._stop_event.is_set():
                assert proc.stdout is not None
                line = proc.stdout.readline()
                if not line:
                    break
                if "on sink" not in line:
                    continue
                log.debug("Auto-switch: sink event: %s", line.strip())
                now = time.monotonic()
                if now - last_eval > 0.5:
                    last_eval = now
                    threading.Thread(target=self._do_evaluate, daemon=True).start()
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()

    def _do_evaluate(self) -> None:
        cfg = load_auto_switch_config()
        if not cfg.get("enabled", False):
            return
        priority: list[str] = cfg.get("output_priority", [])
        if not priority:
            return

        sinks = list_sinks()
        sink_by_name = {s.name: s for s in sinks}
        current_default = _get_default("sink")

        best: str | None = None
        for p in priority:
            if p in sink_by_name and sink_by_name[p].state.upper() == "RUNNING":
                best = p
                break

        if best is None:
            for p in priority:
                if p in sink_by_name:
                    best = p
                    break

        if best and best != current_default:
            log.info("Auto-switch: switching default sink to %s", best)
            ok, _ = set_default_sink(best)
            if ok and self._on_switch:
                GLib.idle_add(self._on_switch, best)


# ── AudioPage ─────────────────────────────────────────────────────────────────

class AudioPage(Gtk.Box):
    """Two-panel Audio manager page."""

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._toast_ov = toast_overlay
        self._sinks: list[Sink] = []
        self._sources: list[Source] = []
        self._streams: list[Stream] = []
        self._cards: list[Card] = []

        self._selected_kind: str | None = None
        self._selected_id: str | None = None
        self._loading = False
        self._cards_collapsed = False
        self._right_panel_sep: Gtk.Separator | None = None
        self._right_scroll: Gtk.ScrolledWindow | None = None

        self._list = Gtk.ListBox()
        self._right_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self._status = Gtk.Label(label="")

        self._monitor = _AutoSwitchMonitor(on_switch=self._on_auto_switched)

        self._build_ui()
        self.refresh()
        self._maybe_start_monitor()

    def _maybe_start_monitor(self) -> None:
        if load_auto_switch_config().get("enabled", False):
            self._monitor.start()

    def _on_auto_switched(self, new_sink_name: str) -> bool:
        sink = next((s for s in self._sinks if s.name == new_sink_name), None)
        label = sink.description if sink else new_sink_name
        utility.toast(self._toast_ov, f"Auto-switched to {label}")
        self.refresh()
        return GLib.SOURCE_REMOVE

    # ── UI build ───────────────────────────────────────────────────

    def _build_ui(self) -> None:
        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        toolbar.set_margin_start(16)
        toolbar.set_margin_end(12)
        toolbar.set_margin_top(10)
        toolbar.set_margin_bottom(6)

        title = Gtk.Label(label="Audio")
        title.add_css_class("heading")
        title.set_xalign(0)
        title.set_hexpand(True)

        self._status.add_css_class("dim-label")
        self._status.add_css_class("caption")

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.add_css_class("flat")
        refresh_btn.set_tooltip_text("Refresh audio state")
        refresh_btn.connect("clicked", lambda _: self.refresh())

        toolbar.append(title)
        toolbar.append(self._status)
        toolbar.append(refresh_btn)

        self.append(toolbar)
        self.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        pane = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        pane.set_vexpand(True)

        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        left.set_size_request(320, -1)

        self._list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._list.add_css_class("navigation-sidebar")
        self._list.connect("row-selected", self._on_row_selected)

        left_scroll = Gtk.ScrolledWindow()
        left_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        left_scroll.set_vexpand(True)
        left_scroll.set_child(self._list)
        left.append(left_scroll)

        self._right_scroll = Gtk.ScrolledWindow()
        self._right_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self._right_scroll.set_hexpand(True)
        self._right_scroll.set_vexpand(True)
        self._right_scroll.set_child(self._right_panel)
        self._right_scroll.set_visible(False)

        self._right_panel_sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        self._right_panel_sep.set_visible(False)

        pane.append(left)
        pane.append(self._right_panel_sep)
        pane.append(self._right_scroll)
        self.append(pane)

    # ── Panel visibility ───────────────────────────────────────────

    def _show_right_panel(self) -> None:
        if self._right_scroll:
            self._right_scroll.set_visible(True)
        if self._right_panel_sep:
            self._right_panel_sep.set_visible(True)

    def _hide_right_panel(self) -> None:
        if self._right_scroll:
            self._right_scroll.set_visible(False)
        if self._right_panel_sep:
            self._right_panel_sep.set_visible(False)

    def _clear_right(self) -> None:
        child = self._right_panel.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self._right_panel.remove(child)
            child = nxt

    # ── Refresh ────────────────────────────────────────────────────

    def refresh(self) -> None:
        if self._loading:
            return
        self._loading = True
        if not _have_tool("pactl"):
            self._status.set_text("pactl not found")
            self._loading = False
            return
        self._status.set_text("Loading...")

        def worker() -> None:
            try:
                sinks = list_sinks()
                sources = list_sources()
                streams = list_streams()
                cards = list_cards()
                GLib.idle_add(self._apply_refresh, sinks, sources, streams, cards)
            except Exception as e:
                log.error("Audio refresh worker failed: %s", e)
                GLib.idle_add(self._apply_refresh, [], [], [], [])

        threading.Thread(target=worker, daemon=True).start()

    def _apply_refresh(
        self,
        sinks: list[Sink],
        sources: list[Source],
        streams: list[Stream],
        cards: list[Card],
    ) -> bool:
        self._loading = False
        self._sinks = sinks
        self._sources = sources
        self._streams = streams
        self._cards = cards

        prev_kind = self._selected_kind
        prev_id = self._selected_id

        self._rebuild_list()

        # Re-select the previously selected item so the detail panel persists
        if prev_kind and prev_id:
            row = self._find_row(prev_kind, prev_id)
            if row:
                self._list.select_row(row)

        self._status.set_text(
            f"{len(sinks)} outputs  \u2022  {len(sources)} inputs  \u2022  {len(streams)} streams"
        )
        return GLib.SOURCE_REMOVE

    # ── List building ──────────────────────────────────────────────

    def _rebuild_list(self) -> None:
        child = self._list.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self._list.remove(child)
            child = nxt

        self._append_section_header("Outputs")
        if self._sinks:
            for sink in self._sinks:
                label = sink.description + (" \u2713" if sink.is_default else "")
                self._append_item_row("sink", sink.name, label, f"{sink.volume}%")
        else:
            self._append_placeholder_row("No outputs found")

        self._append_section_header("Inputs")
        if self._sources:
            for source in self._sources:
                label = source.description + (" \u2713" if source.is_default else "")
                self._append_item_row("source", source.name, label, f"{source.volume}%")
        else:
            self._append_placeholder_row("No inputs found")

        self._append_section_header("Applications")
        if self._streams:
            for stream in self._streams:
                self._append_item_row(
                    "stream", str(stream.index),
                    stream.app_name,
                    f"{stream.media_name} \u2022 {stream.volume}%",
                )
        else:
            self._append_placeholder_row("No active streams")

        self._append_collapsible_section_header("Cards", self._cards_collapsed)
        if not self._cards_collapsed:
            if self._cards:
                for card in self._cards:
                    active = card.profile_descriptions.get(
                        card.active_profile, card.active_profile
                    ) or "none"
                    self._append_item_row("card", card.name, card.name, f"Profile: {active}")
            else:
                self._append_placeholder_row("No audio cards found")

        self._append_section_header("Settings")
        self._append_item_row(
            "autoswitch", "__autoswitch__",
            "Auto-switch Devices",
            "Configure device priority switching",
        )

    def _append_section_header(self, title: str) -> None:
        row = Gtk.ListBoxRow()
        row.set_selectable(False)
        row.set_activatable(False)
        row.add_css_class("sidebar-category-row")
        lbl = Gtk.Label(label=title)
        lbl.set_xalign(0)
        lbl.add_css_class("sidebar-category-label")
        lbl.set_margin_start(12)
        lbl.set_margin_end(12)
        lbl.set_margin_top(10)
        lbl.set_margin_bottom(4)
        row.set_child(lbl)
        self._list.append(row)

    def _append_collapsible_section_header(self, title: str, collapsed: bool) -> None:
        row = Gtk.ListBoxRow()
        row.set_selectable(False)
        row.set_activatable(False)
        row.add_css_class("sidebar-category-row")

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        lbl = Gtk.Label(label=title)
        lbl.set_xalign(0)
        lbl.add_css_class("sidebar-category-label")
        lbl.set_margin_start(12)
        lbl.set_margin_top(10)
        lbl.set_margin_bottom(4)
        lbl.set_hexpand(True)

        icon = "pan-down-symbolic" if not collapsed else "pan-end-symbolic"
        tip = "Collapse" if not collapsed else "Expand"
        toggle_btn = Gtk.Button(icon_name=icon)
        toggle_btn.add_css_class("flat")
        toggle_btn.set_tooltip_text(tip)
        toggle_btn.set_margin_end(6)
        toggle_btn.set_margin_top(4)
        toggle_btn.set_margin_bottom(4)

        def on_toggle(_btn: Gtk.Button) -> None:
            self._cards_collapsed = not self._cards_collapsed
            self._rebuild_list()

        toggle_btn.connect("clicked", on_toggle)
        box.append(lbl)
        box.append(toggle_btn)
        row.set_child(box)
        self._list.append(row)

    def _append_item_row(
        self, kind: str, item_id: str, title: str, subtitle: str = ""
    ) -> None:
        row = Gtk.ListBoxRow()
        row._audio_kind = kind  # type: ignore[attr-defined]
        row._audio_id = item_id  # type: ignore[attr-defined]
        row.add_css_class("sidebar-nav-row")
        action_row = Adw.ActionRow(title=title, subtitle=subtitle)
        action_row.set_activatable(False)
        row.set_child(action_row)
        self._list.append(row)

    def _append_placeholder_row(self, text: str) -> None:
        row = Gtk.ListBoxRow()
        row.set_selectable(False)
        row.set_activatable(False)
        lbl = Gtk.Label(label=text)
        lbl.set_xalign(0)
        lbl.add_css_class("dim-label")
        lbl.add_css_class("caption")
        lbl.set_margin_start(12)
        lbl.set_margin_top(4)
        lbl.set_margin_bottom(4)
        row.set_child(lbl)
        self._list.append(row)

    def _find_row(self, kind: str, item_id: str) -> Gtk.ListBoxRow | None:
        child = self._list.get_first_child()
        while child:
            if isinstance(child, Gtk.ListBoxRow):
                if (
                    getattr(child, "_audio_kind", None) == kind
                    and getattr(child, "_audio_id", None) == item_id
                ):
                    return child
            child = child.get_next_sibling()
        return None

    # ── Selection handling ─────────────────────────────────────────

    def _on_row_selected(
        self, _list: Gtk.ListBox, row: Gtk.ListBoxRow | None
    ) -> None:
        if row is None:
            self._hide_right_panel()
            return
        kind = getattr(row, "_audio_kind", None)
        item_id = getattr(row, "_audio_id", None)
        if not kind or not item_id:
            self._hide_right_panel()
            return

        self._show_right_panel()
        self._selected_kind = kind
        self._selected_id = item_id

        if kind == "sink":
            sink = next((s for s in self._sinks if s.name == item_id), None)
            if sink:
                self._show_sink_detail(sink)
        elif kind == "source":
            source = next((s for s in self._sources if s.name == item_id), None)
            if source:
                self._show_source_detail(source)
        elif kind == "stream":
            stream = next((s for s in self._streams if str(s.index) == item_id), None)
            if stream:
                self._show_stream_detail(stream)
        elif kind == "card":
            card = next((c for c in self._cards if c.name == item_id), None)
            if card:
                self._show_card_detail(card)
        elif kind == "autoswitch":
            self._show_autoswitch_config()

    # ── Detail shell ───────────────────────────────────────────────

    def _build_detail_shell(self, title: str, subtitle: str = "") -> Gtk.Box:
        self._clear_right()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        box.set_margin_start(20)
        box.set_margin_end(20)
        box.set_margin_top(20)
        box.set_margin_bottom(20)

        title_lbl = Gtk.Label(label=title)
        title_lbl.add_css_class("title-2")
        title_lbl.set_xalign(0)
        title_lbl.set_wrap(True)
        box.append(title_lbl)

        if subtitle:
            sub_lbl = Gtk.Label(label=subtitle)
            sub_lbl.set_xalign(0)
            sub_lbl.set_wrap(True)
            sub_lbl.add_css_class("dim-label")
            box.append(sub_lbl)

        self._right_panel.append(box)
        return box

    def _action_result(self, ok: bool, details: str, success: str, fail: str) -> None:
        if ok:
            utility.toast(self._toast_ov, success)
        else:
            if details.strip():
                log.warning("Audio action failed: %s", details.strip())
            utility.toast(self._toast_ov, fail)
        self.refresh()

    # ── Shared volume group builder ────────────────────────────────

    def _make_volume_group(
        self,
        current_vol: int,
        muted: bool,
        on_apply: Any,
        on_mute: Any,
    ) -> Adw.PreferencesGroup:
        grp = Adw.PreferencesGroup(title="Volume")

        vol_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        vol_box.set_margin_start(12)
        vol_box.set_margin_end(12)
        vol_box.set_margin_top(6)
        vol_box.set_margin_bottom(6)

        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 150, 1)
        scale.set_hexpand(True)
        scale.set_value(current_vol)
        scale.add_mark(100, Gtk.PositionType.BOTTOM, None)

        val_lbl = Gtk.Label(label=f"{current_vol}%", width_chars=5, xalign=1.0)
        val_lbl.add_css_class("caption")

        apply_btn = Gtk.Button(label="Apply")
        apply_btn.add_css_class("suggested-action")
        apply_btn.set_valign(Gtk.Align.CENTER)

        scale.connect("value-changed", lambda s: val_lbl.set_text(f"{int(s.get_value())}%"))
        apply_btn.connect("clicked", lambda _: on_apply(int(scale.get_value())))

        vol_box.append(scale)
        vol_box.append(val_lbl)
        vol_box.append(apply_btn)

        vol_row = Adw.ActionRow()
        vol_row.set_activatable(False)
        vol_row.set_child(vol_box)
        grp.add(vol_row)

        mute_row = Adw.SwitchRow(title="Mute")
        mute_row.set_active(muted)
        mute_row.connect("notify::active", lambda sw, _p: on_mute(sw.get_active()))
        grp.add(mute_row)

        return grp

    # ── Sink detail ────────────────────────────────────────────────

    def _show_sink_detail(self, sink: Sink) -> None:
        box = self._build_detail_shell(sink.description)

        vol_grp = self._make_volume_group(
            current_vol=sink.volume,
            muted=sink.muted,
            on_apply=lambda v: self._action_result(
                *set_sink_volume(sink.name, v),
                success="Volume updated",
                fail="Failed to update volume",
            ),
            on_mute=lambda m: self._action_result(
                *set_sink_mute(sink.name, m),
                success="Mute toggled",
                fail="Failed to toggle mute",
            ),
        )
        box.append(vol_grp)

        dev_grp = Adw.PreferencesGroup(title="Device")

        default_row = Adw.ActionRow(
            title="Default Output",
            subtitle="Currently selected as default" if sink.is_default else "",
        )
        def_btn = Gtk.Button(label="Set as Default")
        def_btn.set_valign(Gtk.Align.CENTER)
        def_btn.set_sensitive(not sink.is_default)
        def_btn.connect(
            "clicked",
            lambda _: self._action_result(
                *set_default_sink(sink.name),
                success=f"Default output: {sink.description}",
                fail="Failed to set default output",
            ),
        )
        default_row.add_suffix(def_btn)
        dev_grp.add(default_row)

        if len(sink.ports) > 1:
            port_names = [p.name for p in sink.ports]
            port_labels = [f"{p.description}  ({p.available})" for p in sink.ports]
            port_row = Adw.ComboRow(title="Port")
            port_row.set_model(Gtk.StringList.new(port_labels))
            for i, p in enumerate(sink.ports):
                if p.name == sink.active_port:
                    port_row.set_selected(i)
                    break

            def on_port(row: Adw.ComboRow, _p: Any) -> None:
                idx = row.get_selected()
                if 0 <= idx < len(port_names):
                    self._action_result(
                        *set_sink_port(sink.name, port_names[idx]),
                        success="Port changed",
                        fail="Failed to change port",
                    )

            port_row.connect("notify::selected", on_port)
            dev_grp.add(port_row)

        if sink.sample_spec:
            r = Adw.ActionRow(title="Format", subtitle=sink.sample_spec)
            r.set_activatable(False)
            dev_grp.add(r)

        if sink.state:
            r = Adw.ActionRow(title="State", subtitle=sink.state.capitalize())
            r.set_activatable(False)
            dev_grp.add(r)

        box.append(dev_grp)

        codec = sink.properties.get("api.bluez5.codec", "")
        if codec:
            bt_grp = Adw.PreferencesGroup(title="Bluetooth")
            r = Adw.ActionRow(title="Codec", subtitle=codec.upper())
            r.set_activatable(False)
            bt_grp.add(r)
            profile = sink.properties.get("api.bluez5.profile", "")
            if profile:
                r2 = Adw.ActionRow(title="Profile", subtitle=profile)
                r2.set_activatable(False)
                bt_grp.add(r2)
            box.append(bt_grp)

    # ── Source detail ──────────────────────────────────────────────

    def _show_source_detail(self, source: Source) -> None:
        box = self._build_detail_shell(source.description)

        vol_grp = self._make_volume_group(
            current_vol=source.volume,
            muted=source.muted,
            on_apply=lambda v: self._action_result(
                *set_source_volume(source.name, v),
                success="Volume updated",
                fail="Failed to update volume",
            ),
            on_mute=lambda m: self._action_result(
                *set_source_mute(source.name, m),
                success="Mute toggled",
                fail="Failed to toggle mute",
            ),
        )
        box.append(vol_grp)

        dev_grp = Adw.PreferencesGroup(title="Device")

        default_row = Adw.ActionRow(
            title="Default Input",
            subtitle="Currently selected as default" if source.is_default else "",
        )
        def_btn = Gtk.Button(label="Set as Default")
        def_btn.set_valign(Gtk.Align.CENTER)
        def_btn.set_sensitive(not source.is_default)
        def_btn.connect(
            "clicked",
            lambda _: self._action_result(
                *set_default_source(source.name),
                success=f"Default input: {source.description}",
                fail="Failed to set default input",
            ),
        )
        default_row.add_suffix(def_btn)
        dev_grp.add(default_row)

        if len(source.ports) > 1:
            port_names = [p.name for p in source.ports]
            port_labels = [f"{p.description}  ({p.available})" for p in source.ports]
            port_row = Adw.ComboRow(title="Port")
            port_row.set_model(Gtk.StringList.new(port_labels))
            for i, p in enumerate(source.ports):
                if p.name == source.active_port:
                    port_row.set_selected(i)
                    break

            def on_port(row: Adw.ComboRow, _p: Any) -> None:
                idx = row.get_selected()
                if 0 <= idx < len(port_names):
                    self._action_result(
                        *set_source_port(source.name, port_names[idx]),
                        success="Port changed",
                        fail="Failed to change port",
                    )

            port_row.connect("notify::selected", on_port)
            dev_grp.add(port_row)

        if source.sample_spec:
            r = Adw.ActionRow(title="Format", subtitle=source.sample_spec)
            r.set_activatable(False)
            dev_grp.add(r)

        if source.state:
            r = Adw.ActionRow(title="State", subtitle=source.state.capitalize())
            r.set_activatable(False)
            dev_grp.add(r)

        box.append(dev_grp)

    # ── Stream detail ──────────────────────────────────────────────

    def _show_stream_detail(self, stream: Stream) -> None:
        box = self._build_detail_shell(stream.app_name, stream.media_name)

        vol_grp = self._make_volume_group(
            current_vol=stream.volume,
            muted=stream.muted,
            on_apply=lambda v: self._action_result(
                *set_stream_volume(stream.index, v),
                success="Volume updated",
                fail="Failed to update volume",
            ),
            on_mute=lambda m: self._action_result(
                *set_stream_mute(stream.index, m),
                success="Mute toggled",
                fail="Failed to toggle mute",
            ),
        )
        box.append(vol_grp)

        if self._sinks:
            route_grp = Adw.PreferencesGroup(title="Output Route")
            sink_names = [s.name for s in self._sinks]
            sink_labels = [s.description for s in self._sinks]
            move_row = Adw.ComboRow(title="Send to output")
            move_row.set_model(Gtk.StringList.new(sink_labels))
            for i, s in enumerate(self._sinks):
                if s.name == stream.sink_name:
                    move_row.set_selected(i)
                    break
            apply_move = Gtk.Button(label="Move")
            apply_move.set_valign(Gtk.Align.CENTER)

            def on_move(_: Gtk.Button) -> None:
                idx = int(move_row.get_selected())
                if 0 <= idx < len(sink_names):
                    self._action_result(
                        *move_stream(stream.index, sink_names[idx]),
                        success="Stream moved",
                        fail="Failed to move stream",
                    )

            apply_move.connect("clicked", on_move)
            move_row.add_suffix(apply_move)
            route_grp.add(move_row)
            box.append(route_grp)

    # ── Card detail ────────────────────────────────────────────────

    def _show_card_detail(self, card: Card) -> None:
        friendly = card.name.replace("alsa_card.", "").replace("_", " ").strip()
        box = self._build_detail_shell(friendly, card.driver or "Audio Card")

        grp = Adw.PreferencesGroup(title="Profile")
        profiles = card.profiles or ([card.active_profile] if card.active_profile else [])
        if profiles:
            labels = [card.profile_descriptions.get(p, p) for p in profiles]
            profile_row = Adw.ComboRow(title="Active Profile")
            profile_row.set_model(Gtk.StringList.new(labels))
            for i, p in enumerate(profiles):
                if p == card.active_profile:
                    profile_row.set_selected(i)
                    break
            apply_btn = Gtk.Button(label="Apply")
            apply_btn.set_valign(Gtk.Align.CENTER)

            def on_profile_apply(_: Gtk.Button) -> None:
                idx = int(profile_row.get_selected())
                if 0 <= idx < len(profiles):
                    self._action_result(
                        *set_card_profile(card.name, profiles[idx]),
                        success="Profile changed",
                        fail="Failed to change profile",
                    )

            apply_btn.connect("clicked", on_profile_apply)
            profile_row.add_suffix(apply_btn)
            grp.add(profile_row)
        else:
            r = Adw.ActionRow(title="No profiles available")
            r.set_activatable(False)
            grp.add(r)

        box.append(grp)

    # ── Auto-switch config ─────────────────────────────────────────

    def _show_autoswitch_config(self) -> None:
        box = self._build_detail_shell(
            "Auto-switch Devices",
            "Automatically switch the default output based on device priority.",
        )

        cfg = load_auto_switch_config()
        enabled = bool(cfg.get("enabled", False))
        priority: list[str] = cfg.get("output_priority", [])

        toggle_grp = Adw.PreferencesGroup()
        enabled_row = Adw.SwitchRow(
            title="Enable auto-switch",
            subtitle="Switch to highest-priority active output automatically",
        )
        enabled_row.set_active(enabled)

        def on_enabled_toggle(row: Adw.SwitchRow, _p: Any) -> None:
            c = load_auto_switch_config()
            c["enabled"] = row.get_active()
            save_auto_switch_config(c)
            if row.get_active():
                self._monitor.start()
            else:
                self._monitor.stop()

        enabled_row.connect("notify::active", on_enabled_toggle)
        toggle_grp.add(enabled_row)
        box.append(toggle_grp)

        all_sink_descs = {s.name: s.description for s in self._sinks}

        def rebuild() -> None:
            self._show_autoswitch_config()

        if priority:
            prio_grp = Adw.PreferencesGroup(
                title="Output Priority",
                description="Higher = preferred. Top device is auto-selected when active.",
            )
            for idx, dev_name in enumerate(priority):
                desc = all_sink_descs.get(dev_name, dev_name)
                p_row = Adw.ActionRow(title=desc, subtitle=f"Priority {idx + 1}")
                p_row.set_activatable(False)

                up_btn = Gtk.Button(icon_name="go-up-symbolic")
                up_btn.add_css_class("flat")
                up_btn.set_valign(Gtk.Align.CENTER)
                up_btn.set_sensitive(idx > 0)

                dn_btn = Gtk.Button(icon_name="go-down-symbolic")
                dn_btn.add_css_class("flat")
                dn_btn.set_valign(Gtk.Align.CENTER)
                dn_btn.set_sensitive(idx < len(priority) - 1)

                rm_btn = Gtk.Button(icon_name="list-remove-symbolic")
                rm_btn.add_css_class("flat")
                rm_btn.add_css_class("error")
                rm_btn.set_valign(Gtk.Align.CENTER)
                rm_btn.set_tooltip_text("Remove from priority list")

                def _make_up(i: int) -> Any:
                    def _cb(_b: Gtk.Button) -> None:
                        c = load_auto_switch_config()
                        p = c.get("output_priority", [])
                        if i > 0:
                            p[i - 1], p[i] = p[i], p[i - 1]
                            c["output_priority"] = p
                            save_auto_switch_config(c)
                        rebuild()
                    return _cb

                def _make_dn(i: int) -> Any:
                    def _cb(_b: Gtk.Button) -> None:
                        c = load_auto_switch_config()
                        p = c.get("output_priority", [])
                        if i < len(p) - 1:
                            p[i], p[i + 1] = p[i + 1], p[i]
                            c["output_priority"] = p
                            save_auto_switch_config(c)
                        rebuild()
                    return _cb

                def _make_rm(name: str) -> Any:
                    def _cb(_b: Gtk.Button) -> None:
                        c = load_auto_switch_config()
                        p = c.get("output_priority", [])
                        if name in p:
                            p.remove(name)
                            c["output_priority"] = p
                            save_auto_switch_config(c)
                        rebuild()
                    return _cb

                up_btn.connect("clicked", _make_up(idx))
                dn_btn.connect("clicked", _make_dn(idx))
                rm_btn.connect("clicked", _make_rm(dev_name))
                p_row.add_suffix(up_btn)
                p_row.add_suffix(dn_btn)
                p_row.add_suffix(rm_btn)
                prio_grp.add(p_row)

            box.append(prio_grp)

        unprioritized = [s for s in self._sinks if s.name not in priority]
        if unprioritized:
            add_grp = Adw.PreferencesGroup(title="Add Device to Priority")
            for sink in unprioritized:
                add_row = Adw.ActionRow(title=sink.description)
                add_row.set_activatable(False)
                add_btn = Gtk.Button(icon_name="list-add-symbolic")
                add_btn.add_css_class("flat")
                add_btn.set_valign(Gtk.Align.CENTER)
                add_btn.set_tooltip_text("Add to priority list")

                def _make_add(name: str) -> Any:
                    def _cb(_b: Gtk.Button) -> None:
                        c = load_auto_switch_config()
                        p = c.get("output_priority", [])
                        if name not in p:
                            p.append(name)
                            c["output_priority"] = p
                            save_auto_switch_config(c)
                        rebuild()
                    return _cb

                add_btn.connect("clicked", _make_add(sink.name))
                add_row.add_suffix(add_btn)
                add_grp.add(add_row)
            box.append(add_grp)
