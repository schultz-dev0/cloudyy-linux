"""Cloud Center — timedatectl helpers for Region & Time page."""
from __future__ import annotations

import logging
import os
import subprocess
from dataclasses import dataclass
from datetime import datetime
from zoneinfo import ZoneInfo

log = logging.getLogger(__name__)

POLKIT_AGENT_PATTERN = (
    "hyprpolkitagent|polkit-gnome-authentication-agent|"
    "lxqt-policykit|mate-polkit|polkit-kde-authentication-agent"
)

POLKIT_AGENT_CANDIDATES = (
    "/usr/lib/hyprpolkitagent/hyprpolkitagent",
    "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1",
)

NO_POLKIT_AGENT_MSG = (
    "No polkit authentication agent is available. "
    "Open Cloud Center or run: systemctl --user start hyprpolkitagent.service"
)

AUTH_FAILED_MSG = (
    "Authentication failed or was cancelled."
)


@dataclass
class DateTimeStatus:
    timezone: str = ""
    local_time: str = ""
    universal_time: str = ""
    rtc_time: str = ""
    ntp_enabled: bool = False
    ntp_synchronized: bool = False
    rtc_in_local_tz: bool = False


def polkit_agent_running() -> bool:
    try:
        r = subprocess.run(
            ["pgrep", "-f", POLKIT_AGENT_PATTERN],
            capture_output=True,
            timeout=2,
        )
        return r.returncode == 0
    except Exception:
        return False


def ensure_polkit_agent() -> bool:
    """Ensure a session polkit agent exists (Cloud Center in-app or hyprpolkitagent)."""
    try:
        from lib import polkit_agent

        if polkit_agent.is_registered():
            return True
    except Exception:
        pass

    if polkit_agent_running():
        return True

    try:
        subprocess.run(
            ["systemctl", "--user", "start", "hyprpolkitagent.service"],
            capture_output=True,
            timeout=5,
        )
        if polkit_agent_running():
            return True
    except Exception:
        pass

    for path in POLKIT_AGENT_CANDIDATES:
        if not os.path.isfile(path) or not os.access(path, os.X_OK):
            continue
        try:
            subprocess.Popen(
                [path],
                env=os.environ.copy(),
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return True
        except Exception as e:
            log.warning("Failed to start polkit agent %s: %s", path, e)

    return polkit_agent_running()


def run_timedatectl(args: list[str], timeout: int = 10) -> tuple[bool, str]:
    try:
        r = subprocess.run(
            ["timedatectl"] + args,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        out = (r.stdout + r.stderr).strip()
        return r.returncode == 0, out
    except FileNotFoundError:
        return False, "timedatectl not found"
    except subprocess.TimeoutExpired:
        return False, "timeout"


def run_command_async(
    command: list[str],
    on_complete,
    *,
    timeout: int = 90,
    needs_polkit: bool = False,
) -> None:
    """Run a command on the GTK main thread without blocking the event loop."""
    from gi.repository import Gio, GLib

    if needs_polkit and not ensure_polkit_agent():
        GLib.idle_add(on_complete, False, NO_POLKIT_AGENT_MSG)
        return

    flags = Gio.SubprocessFlags.STDERR_PIPE
    launcher = Gio.SubprocessLauncher.new(flags)
    for key, value in os.environ.items():
        launcher.setenv(key, value, True)

    cancellable = Gio.Cancellable()
    timed_out = {"value": False}

    def on_timeout() -> bool:
        timed_out["value"] = True
        cancellable.cancel()
        return False

    timeout_id = GLib.timeout_add_seconds(timeout, on_timeout)

    try:
        proc = launcher.spawnv(command)
    except GLib.Error as e:
        GLib.source_remove(timeout_id)
        on_complete(False, e.message)
        return

    def on_wait(proc: Gio.Subprocess, result, _user_data=None) -> None:
        GLib.source_remove(timeout_id)
        try:
            proc.wait_finish(result)
            ok = proc.get_exit_status() == 0
            if ok:
                msg = ""
            else:
                _, stderr = proc.communicate_utf8(None, None)
                msg = (stderr or "").strip() or AUTH_FAILED_MSG
        except GLib.Error as e:
            if timed_out["value"]:
                ok, msg = False, (
                    "Authentication timed out — no password dialog appeared. "
                    "Start: /usr/lib/hyprpolkitagent/hyprpolkitagent"
                )
            elif e.matches(Gio.io_error_quark(), Gio.IOErrorEnum.CANCELLED):
                ok, msg = False, "Operation cancelled"
            else:
                ok, msg = False, e.message
        GLib.idle_add(on_complete, ok, msg)

    proc.wait_async(cancellable, on_wait)


def run_timedatectl_async(args: list[str], on_complete, *, timeout: int = 90) -> None:
    """Apply timedatectl changes (uses session polkit — do not wrap in pkexec)."""
    run_command_async(
        ["timedatectl", *args],
        on_complete,
        timeout=timeout,
        needs_polkit=True,
    )


def run_pkexec_async(args: list[str], on_complete, *, timeout: int = 90) -> None:
    """Run pkexec on the GTK main thread (for scripts that must run as root)."""
    run_command_async(["pkexec", *args], on_complete, timeout=timeout, needs_polkit=True)


def run_pkexec(args: list[str], timeout: int = 120) -> tuple[bool, str]:
    """Run a privileged command via polkit (blocking; prefer async helpers from GTK)."""
    if not ensure_polkit_agent():
        return False, NO_POLKIT_AGENT_MSG
    try:
        r = subprocess.run(
            ["pkexec"] + args,
            env=os.environ.copy(),
            timeout=timeout,
        )
        if r.returncode == 0:
            return True, ""
        return False, AUTH_FAILED_MSG
    except FileNotFoundError:
        return False, "pkexec not found"
    except subprocess.TimeoutExpired:
        return False, "Authentication timed out"


def parse_show(output: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in output.splitlines():
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        result[key.strip()] = value.strip()
    return result


def get_status() -> DateTimeStatus:
    ok, out = run_timedatectl(["show"])
    if not ok:
        return DateTimeStatus()

    props = parse_show(out)
    return DateTimeStatus(
        timezone=props.get("Timezone", ""),
        local_time=props.get("LocalRTC", props.get("Local", "")),
        universal_time=props.get("TimeUSec", ""),
        rtc_time=props.get("RTCTimeUSec", ""),
        ntp_enabled=props.get("NTP", "no") == "yes",
        ntp_synchronized=props.get("NTPSynchronized", "no") == "yes",
        rtc_in_local_tz=props.get("LocalRTC", "no") == "yes",
    )


def get_status_text() -> dict[str, str]:
    """Human-readable status lines for the UI."""
    ok, out = run_timedatectl(["status"])
    if not ok:
        return {"summary": out or "timedatectl unavailable"}

    lines = [ln.strip() for ln in out.splitlines() if ln.strip()]
    result: dict[str, str] = {}
    for line in lines:
        if line.startswith("Local time:"):
            result["local_time"] = line.partition(":")[2].strip()
        elif line.startswith("Universal time:"):
            result["universal_time"] = line.partition(":")[2].strip()
        elif line.startswith("RTC time:"):
            result["rtc_time"] = line.partition(":")[2].strip()
        elif line.startswith("Time zone:"):
            result["timezone"] = line.partition(":")[2].strip()
        elif line.startswith("System clock synchronized:"):
            result["ntp_sync"] = line.partition(":")[2].strip()
        elif line.startswith("NTP service:"):
            result["ntp_service"] = line.partition(":")[2].strip()
        elif line.startswith("RTC in local TZ:"):
            result["rtc_local"] = line.partition(":")[2].strip()
    return result


def format_local_clock(timezone: str = "") -> str:
    try:
        tz = ZoneInfo(timezone) if timezone else None
        now = datetime.now(tz)
        return now.strftime("%A, %d %b %Y  %H:%M:%S")
    except Exception:
        return datetime.now().strftime("%A, %d %b %Y  %H:%M:%S")


def get_timezone() -> str:
    ok, out = run_timedatectl(["show", "-p", "Timezone", "--value"])
    return out.strip() if ok else ""


def list_timezones() -> list[str]:
    ok, out = run_timedatectl(["list-timezones"])
    if not ok:
        return []
    return [ln.strip() for ln in out.splitlines() if ln.strip()]


def set_timezone(tz: str) -> tuple[bool, str]:
    ok, out = run_timedatectl(["set-timezone", tz], timeout=120)
    return ok, out if ok else (out or AUTH_FAILED_MSG)


def get_ntp_enabled() -> bool:
    ok, out = run_timedatectl(["show", "-p", "NTP", "--value"])
    return ok and out.strip() == "yes"


def set_ntp(enabled: bool) -> tuple[bool, str]:
    ok, out = run_timedatectl(
        ["set-ntp", "true" if enabled else "false"],
        timeout=120,
    )
    return ok, out if ok else (out or AUTH_FAILED_MSG)


def set_manual_time(dt: datetime) -> tuple[bool, str]:
    value = dt.strftime("%Y-%m-%d %H:%M:%S")
    ok, out = run_timedatectl(["set-time", value], timeout=120)
    return ok, out if ok else (out or AUTH_FAILED_MSG)
