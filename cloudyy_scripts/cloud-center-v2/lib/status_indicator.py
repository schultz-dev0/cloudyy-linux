"""Status indicators — badges and spinners for setting state feedback."""
from __future__ import annotations

import logging
from typing import Optional

from gi.repository import Adw, Gtk, GLib

log = logging.getLogger(__name__)


# ── Status Badge Widget ───────────────────────────────────────────────────────


class StatusBadge(Gtk.Box):
    """Visual indicator for setting state: pending, success, error."""

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        self.set_halign(Gtk.Align.END)
        self.set_valign(Gtk.Align.CENTER)
        self.add_css_class("status-badge")

        # Spinner (hidden by default)
        self._spinner = Gtk.Spinner()
        self.append(self._spinner)

        # Status label
        self._label = Gtk.Label()
        self._label.add_css_class("status-badge-text")
        self.append(self._label)

        self._current_state: str = ""
        self._source_id: Optional[int] = None

    def show_pending(self, message: str = "Applying…") -> None:
        """Show pending state with spinner."""
        if self._source_id:
            GLib.source_remove(self._source_id)

        self._spinner.start()
        self._label.set_text(message)
        self.remove_css_class("status-badge-success")
        self.remove_css_class("status-badge-error")
        self.add_css_class("status-badge-pending")
        self._current_state = "pending"

    def show_success(self, message: str = "✓ Updated", duration_ms: int = 2000) -> None:
        """Show success state with auto-hide."""
        if self._source_id:
            GLib.source_remove(self._source_id)

        self._spinner.stop()
        self._label.set_text(message)
        self.remove_css_class("status-badge-pending")
        self.remove_css_class("status-badge-error")
        self.add_css_class("status-badge-success")
        self._current_state = "success"

        # Auto-hide after duration
        self._source_id = GLib.timeout_add(
            duration_ms, lambda: (self.set_visible(False), False)[1]
        )

    def show_error(self, message: str = "✗ Failed", duration_ms: int = 3000) -> None:
        """Show error state with auto-hide."""
        if self._source_id:
            GLib.source_remove(self._source_id)

        self._spinner.stop()
        self._label.set_text(message)
        self.remove_css_class("status-badge-pending")
        self.remove_css_class("status-badge-success")
        self.add_css_class("status-badge-error")
        self._current_state = "error"

        # Auto-hide after duration
        self._source_id = GLib.timeout_add(
            duration_ms, lambda: (self.set_visible(False), False)[1]
        )

    def clear(self) -> None:
        """Hide badge and reset state."""
        if self._source_id:
            GLib.source_remove(self._source_id)
            self._source_id = None
        self._spinner.stop()
        self.set_visible(False)
        self._current_state = ""


# ── Card Wrapper for Rows (Future) ────────────────────────────────────────────


class CardRow(Gtk.Box):
    """Wraps a row widget in a card-based container with shadow and spacing."""

    def __init__(self, child: Gtk.Widget, add_status_badge: bool = False) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.set_margin_start(12)
        self.set_margin_end(12)
        self.set_margin_top(6)
        self.set_margin_bottom(6)
        self.add_css_class("card-row")

        # Container for row content
        content_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        content_box.append(child)

        # Optional status badge
        self.status_badge: Optional[StatusBadge] = None
        if add_status_badge:
            self.status_badge = StatusBadge()
            self.status_badge.set_visible(False)
            content_box.append(self.status_badge)

        self.append(content_box)

    def show_status(
        self, state: str, message: str = "", duration_ms: int = 2000
    ) -> None:
        """Show status badge with given state."""
        if not self.status_badge:
            return

        self.status_badge.set_visible(True)
        if state == "pending":
            self.status_badge.show_pending(message or "Applying…")
        elif state == "success":
            self.status_badge.show_success(message or "✓ Updated", duration_ms)
        elif state == "error":
            self.status_badge.show_error(message or "✗ Failed", duration_ms)


# ── Visual State Helpers ──────────────────────────────────────────────────────


def add_card_styling(widget: Gtk.Widget) -> None:
    """Add card styling to a widget."""
    widget.add_css_class("card-widget")


def add_disabled_state(widget: Gtk.Widget, disabled: bool = True) -> None:
    """Mark widget as disabled (visual feedback)."""
    if disabled:
        widget.add_css_class("card-widget-disabled")
        widget.set_sensitive(False)
    else:
        widget.remove_css_class("card-widget-disabled")
        widget.set_sensitive(True)
