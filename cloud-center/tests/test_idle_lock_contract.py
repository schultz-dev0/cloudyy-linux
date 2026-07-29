from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
HYPRIDLE_CONFIG = REPO_ROOT / "install/assets/defaults/hypr/hypridle.conf"
PAM_CONFIG = REPO_ROOT / "install/assets/pam/cloudyy-lock"
IDLE_MODULE = REPO_ROOT / ".config/quickshell/modules/idle"
LOCK_CONFIG = REPO_ROOT / ".config/quickshell/lock"
HYPR_AUTOSTART = REPO_ROOT / "install/assets/defaults/hypr/autostart.lua"
SESSION_START = REPO_ROOT / "bin/cloudyy-session-start"
CLOUD_CENTER_CONFIG = REPO_ROOT / "cloud-center/config.yaml"
CLOUD_CENTER_MODEL = REPO_ROOT / "cloud-center/lib/ccd/model.py"


class IdleLockContractTests(unittest.TestCase):
    def test_standalone_lock_uses_session_lock_and_pam(self):
        service = (LOCK_CONFIG / "shell.qml").read_text(encoding="utf-8")
        surface = (LOCK_CONFIG / "LockSurface.qml").read_text(encoding="utf-8")
        qmldir = (IDLE_MODULE / "qmldir").read_text(encoding="utf-8")

        self.assertIn("import Quickshell.Wayland", service)
        self.assertIn("import Quickshell.Services.Pam", service)
        self.assertIn("WlSessionLock", service)
        self.assertIn('config: "cloudyy-lock"', service)
        self.assertIn('user: Quickshell.env("USER")', service)
        self.assertIn("PamResult.Success", service)
        self.assertIn("sessionLock.secure", service)
        self.assertIn("readyFile", service)
        self.assertIn("readonly property bool responseRequired: pam.responseRequired", service)
        self.assertIn("readonly property bool responseVisible: pam.responseVisible", service)
        self.assertIn("readonly property bool authenticating: pam.active", service)
        success_branch = re.search(
            r"if\s*\(\s*result\s*===\s*PamResult\.Success\s*\)\s*"
            r"\{(?P<body>.*?)\}\s*else",
            service,
            re.DOTALL,
        )
        self.assertIsNotNone(success_branch)
        self.assertIn("root.finishUnlock()", success_branch.group("body"))
        self.assertEqual(service.count("sessionLock.locked = false"), 1)
        self.assertNotIn("property WlSessionLock", service)
        self.assertNotIn("pam.message", service)

        self.assertIn("WlSessionLockSurface", surface)
        self.assertIn("echoMode: TextInput.Password", surface)
        self.assertIn("lockService.respond(passwordInput.text)", surface)
        self.assertIn('passwordInput.text = ""', surface)
        self.assertNotIn("pam.message", surface)
        self.assertIn("lockService.errorMessage", surface)
        self.assertIn("FastBlur", surface)
        self.assertIn("radius: 64", surface)
        self.assertIn("Qt.lighter(Theme.textMuted, 1.28)", surface)
        self.assertIn("Theme.glass(Theme.surface_container_lowest", surface)
        self.assertIn("Theme.primary", surface)
        self.assertIn("onResponseRequiredChanged", surface)
        self.assertIn("passwordInput.forceActiveFocus()", surface)
        self.assertIn("workspaceAnimation", surface)
        self.assertIn("lockService.unlocking", surface)
        self.assertIn("NumberAnimation", surface)

        self.assertNotIn("LockService", qmldir)
        self.assertFalse((IDLE_MODULE / "LockService.qml").exists())
        self.assertFalse((IDLE_MODULE / "LockSurface.qml").exists())

    def test_lock_launcher_waits_for_a_secure_session_lock(self):
        launcher = (REPO_ROOT / "bin/cloudyy-lock").read_text(encoding="utf-8")

        self.assertIn("qs -n -d -p", launcher)
        self.assertIn("ready_file", launcher)
        self.assertIn("launcher.lock", launcher)
        self.assertIn("CLOUDYY_LOCK_PROMPT_OUTPUT", launcher)
        self.assertIn("hyprctl cursorpos -j", launcher)
        self.assertIn("CLOUDYY_LOCK_WORKSPACE_ANIMATION", launcher)
        self.assertIn('"workspaces"', launcher)
        self.assertIn("--wait", launcher)
        self.assertIn("did not become secure", launcher)

        service = (LOCK_CONFIG / "shell.qml").read_text(encoding="utf-8")
        self.assertIn("isPromptScreen", service)
        self.assertIn("root.finishUnlock()", service)
        self.assertIn("unlockTimer.restart()", service)
        self.assertRegex(service, r"onTriggered:\s*\{\s*sessionLock\.locked = false")
        self.assertNotIn("CLOUDYY_LOCK_TEST_TIMEOUT", service)

    def test_hypridle_config_exposes_scene_and_lock_timeouts(self):
        source = HYPRIDLE_CONFIG.read_text(encoding="utf-8")

        self.assertRegex(source, r"(?m)^\s*timeout\s*=\s*900\s*$")
        self.assertRegex(source, r"(?m)^\s*timeout\s*=\s*2700\s*$")
        self.assertIn("cloudyy-idle show", source)
        self.assertIn("cloudyy-lock", source)

    def test_cloud_center_exposes_idle_timing_controls(self):
        source = CLOUD_CENTER_CONFIG.read_text(encoding="utf-8")
        model = CLOUD_CENTER_MODEL.read_text(encoding="utf-8")

        self.assertIn("id: idle", source)
        self.assertIn("title: Idle & Lock", source)
        self.assertIn("key: idle/scene_enabled", source)
        self.assertIn("key: idle/scene_minutes", source)
        self.assertIn("key: idle/lock_minutes", source)
        self.assertIn("key: idle/lock_enabled", source)
        self.assertIn("key: idle/lid_sleep", source)
        self.assertIn("default: true", source)
        self.assertIn("default: 15", source)
        self.assertIn("default: 45", source)
        self.assertIn("python3 -m lib.hypridle_persist scene on", source)
        self.assertIn("python3 -m lib.hypridle_persist scene off", source)
        self.assertIn("python3 -m lib.hypridle_persist lock on", source)
        self.assertIn("python3 -m lib.hypridle_persist lock off", source)
        self.assertIn("python3 -m lib.hypridle_persist apply scene {value_i}", source)
        self.assertIn("python3 -m lib.hypridle_persist apply lock {value_i}", source)
        self.assertIn("python3 -m lib.lid_sleep_persist on", source)
        self.assertIn("python3 -m lib.lid_sleep_persist off", source)
        self.assertIn('"idle"', model)

    def test_hyprland_starts_hypridle_not_removed_hyprlock(self):
        source = HYPR_AUTOSTART.read_text(encoding="utf-8")
        starter = SESSION_START.read_text(encoding="utf-8")

        self.assertIn('hl.exec_cmd("cloudyy-session-start")', source)
        self.assertIn("systemctl --user start hypridle.service", starter)
        self.assertNotIn("hyprlock", source)

    def test_autologin_session_is_gated_by_cloudyy_lock(self):
        source = HYPR_AUTOSTART.read_text(encoding="utf-8")
        starter = SESSION_START.read_text(encoding="utf-8")

        self.assertIn('hl.exec_cmd("cloudyy-session-start")', source)
        self.assertIn("cloudyy-lock --wait", starter)
        self.assertLess(
            starter.index("cloudyy-lock --wait"),
            starter.index("systemctl --user start hypridle.service"),
        )

    def test_idle_dispatcher_forwards_only_supported_actions(self):
        dispatcher = (REPO_ROOT / "bin/cloudyy-idle").read_text(encoding="utf-8")
        self.assertIn('ipc call idle activate', dispatcher)
        self.assertIn("dismiss)", dispatcher)
        self.assertIn("lock)", dispatcher)
        self.assertIn("exec cloudyy-lock", dispatcher)
        self.assertIn('hl.dsp.submap("cloudyy-idle")', dispatcher)
        self.assertIn('hl.dsp.submap("reset")', dispatcher)

    def test_idle_submap_consumes_input_until_wake(self):
        bindings = (REPO_ROOT / ".config/hypr/bindings.lua").read_text(encoding="utf-8")
        self.assertIn('hl.define_submap("cloudyy-idle"', bindings)
        self.assertIn('hl.bind("catchall", hl.dsp.exec_cmd("cloudyy-idle dismiss"))', bindings)

    def test_pam_lock_service_uses_system_auth_and_gnome_keyring(self):
        source = PAM_CONFIG.read_text(encoding="utf-8")

        self.assertIn("auth      substack  system-auth", source)
        self.assertIn("pam_gnome_keyring.so", source)
        self.assertIn("auth      optional  pam_gnome_keyring.so auto_start", source)
        self.assertIn("session   optional  pam_gnome_keyring.so auto_start", source)
        self.assertNotIn("pam_exec.so", source)


if __name__ == "__main__":
    unittest.main()
