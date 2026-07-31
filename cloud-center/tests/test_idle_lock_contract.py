from pathlib import Path
import re
import unittest

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
HYPRIDLE_CONFIG = REPO_ROOT / "install/assets/defaults/hypr/hypridle.conf"
PAM_CONFIG = REPO_ROOT / "install/assets/pam/cloudyy-lock"
DEPLOY_SCRIPT = REPO_ROOT / "install/config/deploy.sh"
IDLE_MODULE = REPO_ROOT / ".config/quickshell/modules/idle"
LOCK_CONFIG = REPO_ROOT / ".config/quickshell/lock"
HYPR_AUTOSTART = REPO_ROOT / "install/assets/defaults/hypr/autostart.lua"
SESSION_START = REPO_ROOT / "bin/cloudyy-session-start"
WALLPAPER_RESTORE = REPO_ROOT / "bin/cloudyy-wallpaper-restore"
QUICKSHELL_UNIT = REPO_ROOT / "install/assets/systemd/quickshell.service"
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

    def test_idle_timing_controls_use_editable_dropdown_presets(self):
        config = yaml.safe_load(CLOUD_CENTER_CONFIG.read_text(encoding="utf-8"))
        idle_page = next(page for page in config["pages"] if page["id"] == "idle")
        items = idle_page["layout"][0]["items"]
        controls = {
            item["properties"]["key"]: item
            for item in items
            if item["properties"].get("key")
            in {"idle/scene_minutes", "idle/lock_minutes"}
        }

        expected_controls = {
            "idle/scene_minutes": (15, "scene"),
            "idle/lock_minutes": (45, "lock"),
        }
        self.assertEqual(set(controls), set(expected_controls))

        for key, (default, action) in expected_controls.items():
            control = controls[key]
            properties = control["properties"]

            self.assertEqual(control["type"], "slider")
            self.assertEqual(properties.get("presentation"), "editable_dropdown")
            self.assertEqual(properties["preset_min"], 15)
            self.assertEqual(properties["preset_max"], 120)
            self.assertEqual(properties["preset_step"], 15)
            self.assertEqual(properties["default"], default)
            self.assertNotIn("min", properties)
            self.assertNotIn("max", properties)
            self.assertNotIn("step", properties)
            self.assertIn(
                f"python3 -m lib.hypridle_persist apply {action} {{value_i}}",
                control["on_change"]["command"],
            )

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

    def test_login_restores_wallpaper_without_regenerating_theme(self):
        starter = SESSION_START.read_text(encoding="utf-8")
        restore = WALLPAPER_RESTORE.read_text(encoding="utf-8")

        self.assertIn("cloudyy-wallpaper-restore &", starter)
        self.assertNotIn("cloudyy-theme restore\n", starter)
        self.assertIn('"${client[@]}" img "$wallpaper"', restore)
        self.assertNotIn("matugen", restore)

    def test_login_does_not_privileged_start_geoclue(self):
        starter = SESSION_START.read_text(encoding="utf-8")

        self.assertNotIn("systemctl start geoclue", starter)
        self.assertNotIn("cloudyy-system-monitor", starter)

    def test_quickshell_is_started_only_after_unlock(self):
        starter = SESSION_START.read_text(encoding="utf-8")
        unit = QUICKSHELL_UNIT.read_text(encoding="utf-8")

        self.assertIn("cloudyy-quickshell-start", starter)
        self.assertNotIn("WantedBy=graphical-session.target", unit)
        self.assertLess(
            starter.index("cloudyy-lock --wait"),
            starter.index("cloudyy-quickshell-start"),
        )

    def test_existing_legacy_autostart_is_migrated(self):
        deploy = DEPLOY_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("migrate_legacy_autostart()", deploy)
        self.assertIn("Legacy autostart.lua has manual changes", deploy)
        self.assertIn("managed_tail=", deploy)
        self.assertLess(
            deploy.index("migrate_legacy_autostart()"),
            deploy.index('local hypr_modules=('),
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
