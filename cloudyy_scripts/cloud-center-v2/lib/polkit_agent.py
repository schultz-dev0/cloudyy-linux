"""Cloud Center — in-app polkit authentication agent (native Adw password UI)."""
from __future__ import annotations

import logging
import os
import subprocess
from typing import Callable

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Polkit", "1.0")
gi.require_version("PolkitAgent", "1.0")
from gi.repository import Adw, Gio, GLib, GObject, Gtk, Polkit, PolkitAgent

log = logging.getLogger(__name__)

AGENT_OBJECT_PATH = "/dev/cloudyy/CloudCenter/AuthenticationAgent"
HYPR_POLKIT_SERVICE = "hyprpolkitagent.service"
MAX_AUTH_TRIES = 3

_agent: "CloudCenterPolkitAgent | None" = None
_registered = False


def is_registered() -> bool:
    return _registered


def present_dialog(dialog: Adw.Dialog, parent: Gtk.Window | None) -> None:
    if parent is not None:
        dialog.present(parent)
    else:
        dialog.present()


class AuthenticationDialog(Adw.Dialog):
    """Native Cloud Center password prompt for polkit."""

    def __init__(self, message: str, username: str) -> None:
        super().__init__()
        self.set_title("Authentication Required")
        self.set_content_width(420)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        self._cancel_btn = Gtk.Button(label="Cancel")
        header.pack_start(self._cancel_btn)
        self._auth_btn = Gtk.Button(label="Authenticate")
        self._auth_btn.add_css_class("suggested-action")
        header.pack_end(self._auth_btn)
        toolbar.add_top_bar(header)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_margin_start(16)
        content.set_margin_end(16)
        content.set_margin_top(16)
        content.set_margin_bottom(16)

        info = Gtk.Label(label=message or "Administrator permission is required.")
        info.set_wrap(True)
        info.set_xalign(0)
        content.append(info)

        if username and username != os.getenv("USER", ""):
            user_lbl = Gtk.Label(label=f"User: {username}")
            user_lbl.add_css_class("dim-label")
            user_lbl.set_xalign(0)
            content.append(user_lbl)

        self._info_label = Gtk.Label(label="")
        self._info_label.add_css_class("error")
        self._info_label.set_wrap(True)
        self._info_label.set_xalign(0)
        self._info_label.set_visible(False)
        content.append(self._info_label)

        self._pw_row = Adw.PasswordEntryRow(title="Password")
        grp = Adw.PreferencesGroup()
        grp.add(self._pw_row)
        content.append(grp)

        toolbar.set_content(content)
        self.set_child(toolbar)

    def set_info_message(self, message: str) -> None:
        self._info_label.set_text(message)
        self._info_label.set_visible(bool(message))

    def get_password(self) -> str:
        return self._pw_row.get_text()

    def clear_password(self) -> None:
        self._pw_row.set_text("")

    def focus_password(self) -> None:
        self._pw_row.grab_focus()


class CloudCenterPolkitAgent(PolkitAgent.Listener):
    """Session polkit agent that shows Cloud Center styled dialogs."""

    __gtype_name__ = "CloudCenterPolkitAgent"

    def __init__(self, parent_getter: Callable[[], Gtk.Window | None]) -> None:
        super().__init__()
        self._parent_getter = parent_getter
        self._queue: list[tuple[Gio.Task, dict]] = []
        self._busy = False

    def do_initiate_authentication(
        self,
        action_id: str,
        message: str,
        icon_name: str,
        details: Polkit.Details,
        cookie: str,
        identities: list,
        cancellable: Gio.Cancellable | None,
        callback,
        user_data=None,
    ) -> None:
        task = Gio.Task.new(self, cancellable, callback, user_data)
        self._queue.append((
            task,
            {
                "message": message,
                "cookie": cookie,
                "identities": identities,
                "cancellable": cancellable,
            },
        ))
        GLib.idle_add(self._pump_queue)

    def do_initiate_authentication_finish(self, result) -> bool:
        task = Gio.Task.get(result, GObject.TYPE_TASK)
        try:
            return task.propagate_boolean()
        except GLib.Error as e:
            log.debug("Polkit auth finish: %s", e.message)
            return False

    def _pump_queue(self) -> bool:
        if self._busy or not self._queue:
            return False
        self._busy = True
        task, data = self._queue[0]
        self._prompt(task, data, attempt=0)
        return False

    def _prompt(self, task: Gio.Task, data: dict, attempt: int) -> None:
        identity = _pick_identity(data["identities"])
        parent = self._parent_getter()
        dialog = AuthenticationDialog(data["message"], _identity_name(identity))
        cancellable = data["cancellable"]
        cancel_id = 0

        def cleanup_cancel() -> None:
            if cancel_id and cancellable is not None:
                cancellable.disconnect(cancel_id)

        def finish(cancelled: bool = False, success: bool = False) -> None:
            cleanup_cancel()
            dialog.close()
            self._finish_task(task, cancelled=cancelled, success=success)

        if cancellable is not None:
            cancel_id = cancellable.connect("cancelled", lambda *_: finish(cancelled=True))

        def on_cancel(_btn) -> None:
            finish(cancelled=True)

        def on_auth(_btn) -> None:
            password = dialog.get_password()
            if not password:
                dialog.set_info_message("Enter your password.")
                return
            dialog._auth_btn.set_sensitive(False)
            self._run_session(dialog, identity, data["cookie"], password, attempt, finish)

        dialog._cancel_btn.connect("clicked", on_cancel)
        dialog._auth_btn.connect("clicked", on_auth)
        dialog._pw_row.connect("entry-activated", lambda _: on_auth(None))
        present_dialog(dialog, parent)
        dialog.focus_password()

    def _run_session(
        self,
        dialog: AuthenticationDialog,
        identity: Polkit.Identity,
        cookie: str,
        password: str,
        attempt: int,
        finish,
    ) -> None:
        session = PolkitAgent.Session.new(identity, cookie)

        def on_request(_session, _request: str, _echo_on: bool) -> None:
            _session.response(password)

        def on_error(_session, msg: str) -> None:
            dialog.set_info_message(msg)

        def on_completed(_session, gained_authorization: bool) -> None:
            if gained_authorization:
                finish(success=True)
                return
            if attempt + 1 >= MAX_AUTH_TRIES:
                finish(success=False)
                return
            dialog._auth_btn.set_sensitive(True)
            dialog.clear_password()
            dialog.set_info_message("Authentication failed. Try again.")
            dialog.focus_password()

        session.connect("request", on_request)
        session.connect("show-error", on_error)
        session.connect("show-info", on_error)
        session.connect("completed", on_completed)
        session.initiate()

    def _finish_task(self, task: Gio.Task, *, cancelled: bool, success: bool) -> None:
        if self._queue and self._queue[0][0] is task:
            self._queue.pop(0)
        self._busy = False
        if cancelled:
            task.return_error(
                GLib.GError.new_literal(Polkit.Error.quark(), "Cancelled", Polkit.Error.CANCELLED)
            )
        else:
            task.return_boolean(success)
        GLib.idle_add(self._pump_queue)


def _pick_identity(identities: list) -> Polkit.Identity:
    uid = os.getuid()
    for identity in identities:
        if isinstance(identity, Polkit.UnixUser) and identity.get_uid() == uid:
            return identity
    if identities:
        return identities[0]
    return Polkit.UnixUser.new(uid)


def _identity_name(identity: Polkit.Identity) -> str:
    if isinstance(identity, Polkit.UnixUser):
        try:
            import pwd

            return pwd.getpwuid(identity.get_uid()).pw_name
        except KeyError:
            return str(identity.get_uid())
    return os.getenv("USER", "")


def _stop_fallback_agents() -> None:
    try:
        subprocess.run(
            ["systemctl", "--user", "stop", HYPR_POLKIT_SERVICE],
            capture_output=True,
            timeout=5,
        )
        subprocess.run(["pkill", "-x", "hyprpolkitagent"], capture_output=True, timeout=2)
    except Exception as e:
        log.debug("Could not stop fallback polkit agents: %s", e)


def _restore_fallback_agent() -> None:
    try:
        subprocess.run(
            ["systemctl", "--user", "start", HYPR_POLKIT_SERVICE],
            capture_output=True,
            timeout=5,
        )
    except Exception as e:
        log.debug("Could not restart %s: %s", HYPR_POLKIT_SERVICE, e)


def register(parent_getter: Callable[[], Gtk.Window | None]) -> None:
    """Register Cloud Center as the session polkit authentication agent."""
    global _agent, _registered

    if _registered:
        return

    _stop_fallback_agents()
    _agent = CloudCenterPolkitAgent(parent_getter)

    def on_session(_session_obj, result) -> None:
        global _registered
        try:
            subject = Polkit.UnixSession.new_for_process_finish(result)
        except GLib.Error as e:
            log.warning("Polkit session lookup failed: %s", e.message)
            return

        def try_register(retry: bool = False) -> bool:
            global _registered
            try:
                _agent.register(
                    PolkitAgent.RegisterFlags.NONE,
                    subject,
                    AGENT_OBJECT_PATH,
                    None,
                )
                _registered = True
                log.info("Registered Cloud Center polkit authentication agent")
            except GLib.Error as e:
                if not retry and "already exists" in e.message.lower():
                    _stop_fallback_agents()
                    GLib.timeout_add(300, lambda: try_register(retry=True))
                else:
                    log.warning("Could not register polkit agent: %s", e.message)
            return False

        try_register()

    Polkit.UnixSession.new_for_process(os.getpid(), None, on_session)


def unregister() -> None:
    """Release the agent slot and restore hyprpolkitagent as fallback."""
    global _agent, _registered

    # PolkitAgent.Listener.unregister() can segfault in PyGObject; the session
    # registration is tied to this process and clears on exit.
    _agent = None
    _registered = False
    _restore_fallback_agent()
