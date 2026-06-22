"""Cloud Center — Region & Time page (GeoClue + timedatectl)."""
from __future__ import annotations

import logging
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from gi.repository import Adw, GLib, Gtk, Pango

import lib.datetime_helpers as dt
import lib.geoclue_helpers as geo
import lib.utility as utility

log = logging.getLogger(__name__)


@dataclass
class RefreshSnapshot:
    status_text: dict[str, str]
    timezone: str
    ntp_enabled: bool
    manual: bool
    geo_active: bool
    static: geo.GeoLocation | None
    saved_mode: str
    saved_lat: str
    saved_lon: str
    location: geo.GeoLocation | None = field(default=None)


class RegionTimePage(Gtk.Box):
    """Date/time and system geolocation controls."""

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.toast_overlay = toast_overlay
        self.timezones: list[str] = []
        self.clock_source_id: int = 0
        self.updating = False
        self.tz_busy = False
        self.current_timezone = ""
        self._tz_row_map: dict[str, Gtk.ListBoxRow] = {}
        self._tz_current_row: Gtk.ListBoxRow | None = None
        self._tz_offsets: dict[str, str] = {}

        self.build_ui()
        threading.Thread(target=self.load_timezones_worker, daemon=True).start()
        self.refresh()
        self.clock_source_id = GLib.timeout_add_seconds(1, self.tick_clock)

    def build_ui(self) -> None:
        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        toolbar.set_margin_start(16)
        toolbar.set_margin_end(12)
        toolbar.set_margin_top(10)
        toolbar.set_margin_bottom(6)

        title = Gtk.Label(label="Region & Time")
        title.add_css_class("heading")
        title.set_xalign(0)
        title.set_hexpand(True)

        self.status_label = Gtk.Label(label="")
        self.status_label.add_css_class("dim-label")
        self.status_label.add_css_class("caption")

        self.spinner = Gtk.Spinner()
        self.spinner.set_visible(False)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.add_css_class("flat")
        refresh_btn.set_tooltip_text("Refresh status")
        refresh_btn.connect("clicked", lambda _: self.refresh())

        toolbar.append(title)
        toolbar.append(self.status_label)
        toolbar.append(self.spinner)
        toolbar.append(refresh_btn)
        self.append(toolbar)
        self.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)

        pref = Adw.PreferencesPage()

        time_group = Adw.PreferencesGroup()
        time_group.set_title("Date & Time")
        time_group.set_description(
            "Timezone and clock settings. Manual time requires NTP sync to be disabled."
        )

        self.clock_row = Adw.ActionRow(title="Local Time")
        self.clock_row.set_subtitle("Loading…")
        self.clock_row.set_activatable(False)
        time_group.add(self.clock_row)

        self.tz_current_row = Adw.ActionRow(title="Current Timezone")
        self.tz_current_row.set_subtitle("—")
        self.tz_current_row.set_activatable(False)
        time_group.add(self.tz_current_row)

        self.ntp_row = Adw.SwitchRow(title="Network Time (NTP)")
        self.ntp_row.set_subtitle("Synchronize clock automatically")
        self.ntp_row.connect("notify::active", self.on_ntp_changed)
        time_group.add(self.ntp_row)

        self.ntp_status_row = Adw.ActionRow(title="Sync Status")
        self.ntp_status_row.set_subtitle("—")
        self.ntp_status_row.set_activatable(False)
        time_group.add(self.ntp_status_row)

        tz_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        tz_box.set_margin_start(12)
        tz_box.set_margin_end(12)
        tz_box.set_margin_top(8)
        tz_box.set_margin_bottom(8)

        tz_label = Gtk.Label(label="Timezone")
        tz_label.set_xalign(0)
        tz_label.add_css_class("heading")
        tz_box.append(tz_label)

        self.tz_search = Gtk.SearchEntry()
        self.tz_search.set_placeholder_text("Search timezones…")
        self.tz_search.connect("search-changed", lambda _: self.refilter_timezones())
        tz_box.append(self.tz_search)

        self.tz_list = Gtk.ListBox()
        self.tz_list.set_selection_mode(Gtk.SelectionMode.NONE)
        self.tz_list.set_activate_on_single_click(True)
        self.tz_list.add_css_class("navigation-sidebar")
        self.tz_list.set_filter_func(self._tz_filter_func)
        self.tz_list.connect("row-activated", self.on_timezone_activated)

        self.tz_scroll = Gtk.ScrolledWindow()
        self.tz_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.tz_scroll.set_min_content_height(240)
        self.tz_scroll.set_child(self.tz_list)
        tz_box.append(self.tz_scroll)

        self.tz_empty_label = Gtk.Label()
        self.tz_empty_label.add_css_class("dim-label")
        self.tz_empty_label.set_margin_top(10)
        self.tz_empty_label.set_margin_bottom(10)
        self.tz_empty_label.set_visible(False)
        tz_box.append(self.tz_empty_label)

        tz_group = Adw.PreferencesGroup()
        tz_group.add(tz_box)
        time_group.add(tz_group)

        manual_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        manual_box.set_margin_start(12)
        manual_box.set_margin_end(12)
        manual_box.set_margin_top(8)
        manual_box.set_margin_bottom(8)

        manual_label = Gtk.Label(label="Manual Date & Time")
        manual_label.set_xalign(0)
        manual_label.add_css_class("heading")
        manual_box.append(manual_label)

        manual_hint = Gtk.Label(
            label="Disable NTP above to set the clock manually.",
            xalign=0,
        )
        manual_hint.add_css_class("dim-label")
        manual_hint.add_css_class("caption")
        manual_hint.set_wrap(True)
        manual_box.append(manual_hint)

        cal_time = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        self.calendar = Gtk.Calendar()
        cal_time.append(self.calendar)

        spin_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        hour_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        hour_box.append(Gtk.Label(label="Hour"))
        self.hour_spin = Gtk.SpinButton.new_with_range(0, 23, 1)
        self.hour_spin.set_numeric(True)
        hour_box.append(self.hour_spin)
        spin_box.append(hour_box)

        min_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        min_box.append(Gtk.Label(label="Minute"))
        self.minute_spin = Gtk.SpinButton.new_with_range(0, 59, 1)
        self.minute_spin.set_numeric(True)
        min_box.append(self.minute_spin)
        spin_box.append(min_box)
        cal_time.append(spin_box)
        manual_box.append(cal_time)

        self.apply_time_btn = Gtk.Button(label="Apply Manual Time")
        self.apply_time_btn.add_css_class("suggested-action")
        self.apply_time_btn.set_halign(Gtk.Align.START)
        self.apply_time_btn.connect("clicked", self.on_apply_manual_time)
        manual_box.append(self.apply_time_btn)

        manual_group = Adw.PreferencesGroup()
        manual_group.add(manual_box)
        time_group.add(manual_group)

        pref.add(time_group)

        loc_group = Adw.PreferencesGroup()
        loc_group.set_title("Location")
        loc_group.set_description(
            "System geolocation via GeoClue. IP-based location may be inaccurate abroad; "
            "use manual coordinates for a fixed position."
        )

        self.geo_service_row = Adw.ActionRow(title="GeoClue Service")
        self.geo_service_row.set_subtitle("—")
        self.geo_service_row.set_activatable(False)
        loc_group.add(self.geo_service_row)

        self.location_row = Adw.ActionRow(title="Current Location")
        self.location_row.set_subtitle("—")
        self.location_row.set_activatable(False)
        loc_group.add(self.location_row)

        self.manual_mode_row = Adw.SwitchRow(title="Manual Static Location")
        self.manual_mode_row.set_subtitle("Override automatic IP/WiFi geolocation")
        self.manual_mode_row.connect("notify::active", self.on_manual_mode_changed)
        loc_group.add(self.manual_mode_row)

        coords_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        coords_box.set_margin_start(12)
        coords_box.set_margin_end(12)
        coords_box.set_margin_top(8)
        coords_box.set_margin_bottom(8)

        lat_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        lat_box.append(Gtk.Label(label="Latitude"))
        self.lat_spin = Gtk.SpinButton.new_with_range(-90, 90, 0.0001)
        self.lat_spin.set_digits(4)
        self.lat_spin.set_numeric(True)
        lat_box.append(self.lat_spin)
        coords_box.append(lat_box)

        lon_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        lon_box.append(Gtk.Label(label="Longitude"))
        self.lon_spin = Gtk.SpinButton.new_with_range(-180, 180, 0.0001)
        self.lon_spin.set_digits(4)
        self.lon_spin.set_numeric(True)
        lon_box.append(self.lon_spin)
        coords_box.append(lon_box)

        acc_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        acc_box.append(Gtk.Label(label="Accuracy (m)"))
        self.acc_spin = Gtk.SpinButton.new_with_range(1, 50000, 1)
        self.acc_spin.set_value(200)
        self.acc_spin.set_numeric(True)
        acc_box.append(self.acc_spin)
        coords_box.append(acc_box)

        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.apply_loc_btn = Gtk.Button(label="Apply Location")
        self.apply_loc_btn.add_css_class("suggested-action")
        self.apply_loc_btn.connect("clicked", self.on_apply_location)
        btn_row.append(self.apply_loc_btn)

        self.clear_loc_btn = Gtk.Button(label="Use Automatic")
        self.clear_loc_btn.connect("clicked", self.on_clear_location)
        btn_row.append(self.clear_loc_btn)
        coords_box.append(btn_row)

        coords_group = Adw.PreferencesGroup()
        coords_group.add(coords_box)
        loc_group.add(coords_group)

        pref.add(loc_group)
        scroll.set_child(pref)
        self.append(scroll)

        self.update_manual_controls()

    def refresh(self) -> None:
        self.spinner.set_visible(True)
        self.spinner.start()
        threading.Thread(target=self.refresh_worker, daemon=True).start()

    def refresh_worker(self) -> None:
        snapshot = RefreshSnapshot(
            status_text=dt.get_status_text(),
            timezone=dt.get_timezone(),
            ntp_enabled=dt.get_ntp_enabled(),
            manual=geo.is_manual_mode(),
            geo_active=geo.service_active(),
            static=geo.read_static_geolocation(),
            saved_mode=utility.load_setting("region/location_mode", "auto"),
            saved_lat=utility.load_setting("region/manual_lat", ""),
            saved_lon=utility.load_setting("region/manual_lon", ""),
            location=geo.get_location(),  # safe: runs in background thread
        )
        GLib.idle_add(self.finish_refresh, snapshot)

    def finish_refresh(self, snapshot: RefreshSnapshot) -> bool:
        self.apply_refresh_ui(snapshot, snapshot.location)
        return False

    def apply_refresh_ui(
        self,
        snapshot: RefreshSnapshot,
        location: geo.GeoLocation | None,
    ) -> None:
        self.updating = True
        self.spinner.stop()
        self.spinner.set_visible(False)

        timezone = snapshot.timezone
        self.current_timezone = timezone
        self.status_label.set_text(timezone or "Ready")

        self.clock_row.set_subtitle(dt.format_local_clock(timezone))
        self.tz_current_row.set_subtitle(
            snapshot.status_text.get("timezone", timezone) or timezone or "—"
        )

        self.ntp_row.set_active(snapshot.ntp_enabled)
        sync = snapshot.status_text.get("ntp_sync", "unknown")
        service = snapshot.status_text.get("ntp_service", "unknown")
        self.ntp_status_row.set_subtitle(f"Synchronized: {sync}  ·  NTP: {service}")

        self.geo_service_row.set_subtitle(
            "Running" if snapshot.geo_active else "Not running — install/start geoclue"
        )
        self.location_row.set_subtitle(geo.format_location(location))

        self.manual_mode_row.set_active(snapshot.manual or snapshot.saved_mode == "manual")
        if snapshot.static is not None:
            self.lat_spin.set_value(snapshot.static.latitude)
            self.lon_spin.set_value(snapshot.static.longitude)
            self.acc_spin.set_value(snapshot.static.accuracy)
        elif snapshot.saved_lat and snapshot.saved_lon:
            try:
                self.lat_spin.set_value(float(snapshot.saved_lat))
                self.lon_spin.set_value(float(snapshot.saved_lon))
            except ValueError:
                pass

        try:
            tz = ZoneInfo(timezone) if timezone else None
            now = datetime.now(tz)
        except Exception:
            now = datetime.now()
        self.calendar.select_day(now.day)
        self.calendar.select_month(now.month - 1, now.year)
        self.hour_spin.set_value(now.hour)
        self.minute_spin.set_value(now.minute)

        self.update_manual_controls()
        self._update_tz_highlight(timezone)
        self.updating = False

    def tick_clock(self) -> bool:
        self.clock_row.set_subtitle(dt.format_local_clock(self.current_timezone))
        return True

    def load_timezones_worker(self) -> None:
        zones = dt.list_timezones()
        # Pre-compute UTC offsets so the main thread doesn't have to.
        now_utc = datetime.now(timezone.utc)
        offsets: dict[str, str] = {}
        for tz in zones:
            try:
                tz_info = ZoneInfo(tz)
                off = now_utc.astimezone(tz_info).utcoffset()
                if off is not None:
                    total = int(off.total_seconds() // 60)
                    sign = "+" if total >= 0 else "-"
                    abs_m = abs(total)
                    offsets[tz] = f"UTC{sign}{abs_m // 60:02d}:{abs_m % 60:02d}"
                else:
                    offsets[tz] = ""
            except Exception:
                offsets[tz] = ""
        GLib.idle_add(self.set_timezones, zones, offsets)

    def set_timezones(self, zones: list[str], offsets: dict[str, str]) -> bool:
        self.timezones = zones
        self._tz_offsets = offsets
        for tz in zones:
            row = self.make_tz_row(tz, offsets.get(tz, ""))
            self._tz_row_map[tz] = row
            self.tz_list.append(row)
        self._update_tz_highlight(self.current_timezone)
        GLib.idle_add(self._scroll_to_current_tz)
        return False

    def _tz_filter_func(self, row: Gtk.ListBoxRow) -> bool:
        q = self.tz_search.get_text().strip().lower()
        tz = getattr(row, "tz_name", None)
        return tz is not None and (not q or q in tz.lower())

    def refilter_timezones(self) -> None:
        q = self.tz_search.get_text().strip().lower()
        self.tz_list.invalidate_filter()
        # Show/hide "no results" label without touching widgets.
        if q and self.timezones:
            has_match = any(q in tz.lower() for tz in self.timezones)
            self.tz_empty_label.set_visible(not has_match)
            if not has_match:
                self.tz_empty_label.set_text(f"No results for '{q}'")
        else:
            self.tz_empty_label.set_visible(False)

    def make_tz_row(self, tz: str, utc_offset: str = "") -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row.tz_name = tz
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.set_margin_top(6)
        box.set_margin_bottom(6)

        lbl = Gtk.Label(label=tz, xalign=0, hexpand=True)
        lbl.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        box.append(lbl)

        if utc_offset:
            off_lbl = Gtk.Label(label=utc_offset)
            off_lbl.add_css_class("dim-label")
            off_lbl.add_css_class("caption")
            box.append(off_lbl)

        check = Gtk.Image.new_from_icon_name("object-select-symbolic")
        check.set_pixel_size(14)
        check.add_css_class("accent")
        check.set_visible(False)
        row.check_img = check
        box.append(check)

        row.set_child(box)
        return row

    def _update_tz_highlight(self, tz: str) -> None:
        if self._tz_current_row is not None:
            self._tz_current_row.check_img.set_visible(False)
            self._tz_current_row = None
        row = self._tz_row_map.get(tz)
        if row is not None:
            row.check_img.set_visible(True)
            self._tz_current_row = row

    def _scroll_to_current_tz(self) -> bool:
        row = self._tz_row_map.get(self.current_timezone)
        if row is None or not row.get_mapped():
            return False
        alloc = row.get_allocation()
        if alloc.height == 0:
            return False
        adj = self.tz_scroll.get_vadjustment()
        target = alloc.y + alloc.height / 2 - adj.get_page_size() / 2
        adj.set_value(max(0.0, min(target, adj.get_upper() - adj.get_page_size())))
        return False

    def update_manual_controls(self) -> None:
        ntp_on = self.ntp_row.get_active()
        manual_on = self.manual_mode_row.get_active()
        manual_sensitive = not ntp_on

        self.calendar.set_sensitive(manual_sensitive)
        self.hour_spin.set_sensitive(manual_sensitive)
        self.minute_spin.set_sensitive(manual_sensitive)
        self.apply_time_btn.set_sensitive(manual_sensitive)

        self.lat_spin.set_sensitive(manual_on)
        self.lon_spin.set_sensitive(manual_on)
        self.acc_spin.set_sensitive(manual_on)
        self.apply_loc_btn.set_sensitive(manual_on)

    def show_toast(self, message: str, timeout: int = 3) -> None:
        utility.toast(self.toast_overlay, message, timeout)

    def run_privileged(self, command: list[str], on_complete) -> None:
        """Run pkexec on the GTK main thread (for root-only helper scripts)."""
        dt.run_pkexec_async(command, on_complete)

    def on_ntp_changed(self, row: Adw.SwitchRow, _pspec) -> None:
        if self.updating:
            return
        enabled = row.get_active()
        self.update_manual_controls()

        def finish(ok: bool, msg: str) -> bool:
            if ok:
                self.show_toast(f"NTP {'enabled' if enabled else 'disabled'}")
            else:
                self.show_toast(f"NTP change failed: {msg}", 5)
                self.updating = True
                self.ntp_row.set_active(not enabled)
                self.updating = False
            self.refresh()
            return False

        dt.set_ntp_dbus_async(enabled, finish)

    def on_timezone_activated(self, _list: Gtk.ListBox, row: Gtk.ListBoxRow) -> None:
        if self.tz_busy or not getattr(row, "tz_name", None):
            return
        tz = row.tz_name
        if tz == self.current_timezone:
            return

        self.tz_busy = True
        self.status_label.set_text(f"Applying {tz}…")
        self.spinner.set_visible(True)
        self.spinner.start()

        def finish(ok: bool, msg: str) -> bool:
            self.tz_busy = False
            if ok:
                self.current_timezone = tz
                self._update_tz_highlight(tz)
                self.show_toast(f"Timezone set to {tz}")
            else:
                self.show_toast(f"Timezone change failed: {msg}", 5)
            self.refresh()
            return False

        dt.set_timezone_dbus_async(tz, finish)

    def on_apply_manual_time(self, _btn: Gtk.Button) -> None:
        if self.ntp_row.get_active():
            self.show_toast("Disable NTP before setting manual time", 4)
            return
        year, month, day = self.calendar.get_date()
        hour = int(self.hour_spin.get_value())
        minute = int(self.minute_spin.get_value())
        try:
            tz_info = ZoneInfo(self.current_timezone) if self.current_timezone else None
        except Exception:
            tz_info = None
        local_dt = datetime(year, month + 1, day, hour, minute, tzinfo=tz_info)
        utc_usec = int(local_dt.timestamp() * 1_000_000)

        def finish(ok: bool, msg: str) -> bool:
            if ok:
                self.show_toast("Clock updated")
            else:
                self.show_toast(f"Time change failed: {msg}", 5)
            self.refresh()
            return False

        dt.set_time_dbus_async(utc_usec, finish)

    def on_manual_mode_changed(self, row: Adw.SwitchRow, _pspec) -> None:
        if self.updating:
            return
        manual = row.get_active()
        utility.save_setting("region/location_mode", "manual" if manual else "auto")
        self.update_manual_controls()
        if not manual:
            self.run_privileged(geo.clear_location_pkexec_args(), self.on_location_cleared)

    def on_apply_location(self, _btn: Gtk.Button) -> None:
        lat = self.lat_spin.get_value()
        lon = self.lon_spin.get_value()
        acc = self.acc_spin.get_value()
        utility.save_setting("region/manual_lat", str(lat))
        utility.save_setting("region/manual_lon", str(lon))

        def finish(ok: bool, msg: str) -> bool:
            if ok:
                utility.save_setting("region/location_mode", "manual")
                self.show_toast("Static location applied")
            else:
                self.show_toast(f"Location failed: {msg}", 5)
            self.refresh()
            return False

        self.run_privileged(
            geo.manual_location_pkexec_args(lat, lon, accuracy=acc),
            finish,
        )

    def on_clear_location(self, _btn: Gtk.Button) -> None:
        utility.save_setting("region/location_mode", "auto")
        self.run_privileged(geo.clear_location_pkexec_args(), self.on_location_cleared)

    def on_location_cleared(self, ok: bool, msg: str) -> bool:
        if ok:
            self.updating = True
            self.manual_mode_row.set_active(False)
            self.updating = False
            self.show_toast("Automatic location restored")
        else:
            self.show_toast(f"Clear failed: {msg}", 5)
        self.refresh()
        return False

    def do_unroot(self) -> None:
        if self.clock_source_id:
            GLib.source_remove(self.clock_source_id)
            self.clock_source_id = 0
        Gtk.Box.do_unroot(self)
