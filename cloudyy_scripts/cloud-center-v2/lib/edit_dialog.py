"""Edit dialogs for Cloud Center settings — preview-before-apply workflow.

Generic SettingEditDialog + specialized dialogs for each row type:
- Toggle: Simple on/off with preview
- Slider: Value + {value_f} templating
- Selection: Combo with options
- Label: Read-only (no edit dialog)
"""
from __future__ import annotations

import logging
from typing import Callable, Optional, Any

from gi.repository import Adw, Gtk, GLib

log = logging.getLogger(__name__)

_DEFAULT_WIDTH = 520
_DEFAULT_HEIGHT = 420
_SELECTION_MIN_HEIGHT = 360


# ── Generic Edit Dialog ───────────────────────────────────────────────────────


class SettingEditDialog(Adw.Dialog):
    """Base class for setting edit dialogs with preview/apply workflow."""

    def __init__(
        self,
        title: str,
        current_value: Any = None,
        on_preview: Optional[Callable[[Any], None]] = None,
        on_apply: Optional[Callable[[Any], None]] = None,
        *,
        content_width: int = _DEFAULT_WIDTH,
        content_height: int = _DEFAULT_HEIGHT,
    ) -> None:
        super().__init__()
        self.set_title(title)
        self.set_content_width(content_width)
        self.set_content_height(content_height)

        self.current_value = current_value
        self.on_preview = on_preview
        self.on_apply = on_apply
        self._preview_applied = False

        self._build_ui()

    def _build_ui(self) -> None:
        """Build dialog UI: header, content, footer buttons."""
        toolbar = Adw.ToolbarView()

        # Header bar with title
        header = Adw.HeaderBar()
        header.set_show_title(True)
        toolbar.add_top_bar(header)

        # Content area (override in subclasses)
        content_box = self._build_content()
        toolbar.set_content(content_box)

        # Footer buttons
        footer = Gtk.ActionBar()
        footer.set_hexpand(True)

        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _: self.close())
        footer.pack_start(cancel_btn)

        self._preview_btn = Gtk.Button(label="Preview")
        self._preview_btn.add_css_class("suggested-action")
        self._preview_btn.connect("clicked", self._on_preview_clicked)
        footer.pack_end(self._preview_btn)

        apply_btn = Gtk.Button(label="Apply")
        apply_btn.add_css_class("suggested-action")
        apply_btn.connect("clicked", self._on_apply_clicked)
        footer.pack_end(apply_btn)

        toolbar.add_bottom_bar(footer)
        self.set_child(toolbar)

    def _build_content(self) -> Gtk.Widget:
        """Build content area. Override in subclasses."""
        placeholder = Gtk.Box()
        placeholder.set_hexpand(True)
        placeholder.set_vexpand(True)
        return placeholder

    def _on_preview_clicked(self, button: Gtk.Button) -> None:
        """Execute preview command without persisting."""
        new_value = self._get_value()
        if self.on_preview and new_value is not None:
            self.on_preview(new_value)
            self._preview_applied = True
            button.set_label("Preview (applied)")
            button.set_sensitive(False)

    def _on_apply_clicked(self, button: Gtk.Button) -> None:
        """Apply value and close dialog."""
        new_value = self._get_value()
        if self.on_apply and new_value is not None:
            self.on_apply(new_value)
        self.close()

    def _get_value(self) -> Any:
        """Get current value from widget. Override in subclasses."""
        return None


# ── Specialized Dialogs ───────────────────────────────────────────────────────


class ToggleEditDialog(SettingEditDialog):
    """Dialog for editing toggle values."""

    def _build_content(self) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        box.set_margin_start(16)
        box.set_margin_end(16)
        box.set_margin_top(16)
        box.set_margin_bottom(16)

        label = Gtk.Label(label="Toggle Setting")
        label.add_css_class("title-2")
        box.append(label)

        self._switch = Gtk.Switch()
        self._switch.set_active(bool(self.current_value))
        self._switch.set_halign(Gtk.Align.START)
        self._switch.set_margin_top(12)
        box.append(self._switch)

        return box

    def _get_value(self) -> bool:
        return self._switch.get_active()


class SliderEditDialog(SettingEditDialog):
    """Dialog for editing slider values."""

    def __init__(
        self,
        title: str,
        current_value: float = 0.0,
        min_value: float = 0.0,
        max_value: float = 100.0,
        step: float = 1.0,
        on_preview: Optional[Callable] = None,
        on_apply: Optional[Callable] = None,
    ) -> None:
        self.min_value = min_value
        self.max_value = max_value
        self.step = step
        super().__init__(title, current_value, on_preview, on_apply)

    def _build_content(self) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        box.set_margin_start(16)
        box.set_margin_end(16)
        box.set_margin_top(16)
        box.set_margin_bottom(16)

        label = Gtk.Label(label="Adjust Value")
        label.add_css_class("title-2")
        box.append(label)

        # Value display
        self._value_label = Gtk.Label()
        box.append(self._value_label)

        # Slider
        self._scale = Gtk.Scale(
            orientation=Gtk.Orientation.HORIZONTAL,
            adjustment=Gtk.Adjustment(
                value=float(self.current_value),
                lower=self.min_value,
                upper=self.max_value,
                step_increment=self.step,
            ),
        )
        self._scale.set_draw_value(False)
        self._scale.connect("value-changed", self._on_scale_changed)
        box.append(self._scale)

        self._on_scale_changed()
        return box

    def _on_scale_changed(self) -> None:
        value = self._scale.get_value()
        self._value_label.set_text(f"{value:.1f}")

    def _get_value(self) -> float:
        return self._scale.get_value()


class SelectionEditDialog(SettingEditDialog):
    """Dialog for editing selection (enum) values."""

    def __init__(
        self,
        title: str,
        current_value: str = "",
        options: Optional[dict[str, str]] = None,
        on_preview: Optional[Callable] = None,
        on_apply: Optional[Callable] = None,
    ) -> None:
        self.options = options or {}
        option_count = max(len(self.options), 1)
        height = min(640, max(_SELECTION_MIN_HEIGHT, 120 + option_count * 36))
        super().__init__(
            title,
            current_value,
            on_preview,
            on_apply,
            content_height=height,
        )

    def _build_content(self) -> Gtk.Widget:
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        outer.set_margin_start(16)
        outer.set_margin_end(16)
        outer.set_margin_top(16)
        outer.set_margin_bottom(16)
        outer.set_vexpand(True)

        label = Gtk.Label(label="Select Option")
        label.add_css_class("title-2")
        label.set_xalign(0)
        outer.append(label)

        self._list_box = Gtk.ListBox()
        self._list_box.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._list_box.add_css_class("boxed-list")

        self._row_by_key: dict[str, Gtk.ListBoxRow] = {}
        for key, label_text in self.options.items():
            row = Adw.ActionRow(title=label_text)
            row.set_activatable(True)
            row._option_key = key  # type: ignore[attr-defined]
            self._list_box.append(row)
            self._row_by_key[key] = row
            if key == self.current_value:
                self._list_box.select_row(row)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)
        scroll.set_min_content_height(_SELECTION_MIN_HEIGHT - 80)
        scroll.set_child(self._list_box)
        outer.append(scroll)

        return outer

    def _get_value(self) -> str:
        row = self._list_box.get_selected_row()
        if row is None:
            return self.current_value or ""
        return getattr(row, "_option_key", self.current_value) or ""


class TextEditDialog(SettingEditDialog):
    """Dialog for editing text values (e.g., command arguments)."""

    def _build_content(self) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        box.set_margin_start(16)
        box.set_margin_end(16)
        box.set_margin_top(16)
        box.set_margin_bottom(16)

        label = Gtk.Label(label="Edit Value")
        label.add_css_class("title-2")
        box.append(label)

        self._entry = Gtk.Entry()
        self._entry.set_text(str(self.current_value or ""))
        self._entry.set_hexpand(True)
        box.append(self._entry)

        return box

    def _get_value(self) -> str:
        return self._entry.get_text()


# ── Dialog Factory ────────────────────────────────────────────────────────────


def create_edit_dialog(
    row_type: str,
    title: str,
    current_value: Any = None,
    options: Optional[dict[str, str]] = None,
    min_val: float = 0.0,
    max_val: float = 100.0,
    step: float = 1.0,
    on_preview: Optional[Callable] = None,
    on_apply: Optional[Callable] = None,
) -> Optional[SettingEditDialog]:
    """Factory function to create appropriate dialog for row type."""
    if row_type == "toggle":
        return ToggleEditDialog(title, current_value, on_preview, on_apply)
    elif row_type == "slider":
        return SliderEditDialog(
            title, current_value, min_val, max_val, step, on_preview, on_apply
        )
    elif row_type == "selection":
        return SelectionEditDialog(title, current_value, options, on_preview, on_apply)
    elif row_type == "label":
        return None  # Labels are not editable
    else:
        return TextEditDialog(title, current_value, on_preview, on_apply)


def present_edit_dialog(dialog: Adw.Dialog, parent: Gtk.Widget | None) -> None:
    """Present an edit dialog with a sensible parent window."""
    root = parent.get_root() if parent is not None else None
    if isinstance(root, Gtk.Window):
        dialog.present(root)
    elif parent is not None:
        dialog.present(parent)
    else:
        dialog.present()
