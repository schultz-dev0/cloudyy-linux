from pathlib import Path
import unittest

from lib.ccd import model


REPO_ROOT = Path(__file__).resolve().parents[3]
SHELL = REPO_ROOT / ".config/quickshell/cloud-center/shell.qml"
BACKEND = REPO_ROOT / ".config/quickshell/cloud-center/services/Backend.qml"
PAGE = REPO_ROOT / ".config/quickshell/cloud-center/pages/AudioEditor.qml"
PANEL = REPO_ROOT / ".config/quickshell/cloud-center/components/AudioDevicePanel.qml"
COMPONENTS = REPO_ROOT / ".config/quickshell/cloud-center/components"
STAGED_PAGE = Path(__file__).resolve().parents[1] / (
    ".superpowers/sdd/task5-staging/.config/quickshell/cloud-center/pages/AudioEditor.qml"
)
STAGED_PANEL = Path(__file__).resolve().parents[1] / (
    ".superpowers/sdd/task5-staging/.config/quickshell/cloud-center/components/AudioDevicePanel.qml"
)
STAGED_BACKEND = Path(__file__).resolve().parents[1] / (
    ".superpowers/sdd/task5-staging/.config/quickshell/cloud-center/services/Backend.qml"
)
TASK6_STAGING = Path(__file__).resolve().parents[1] / ".superpowers/sdd/task6-staging"
STAGED_TASK6_PAGE = TASK6_STAGING / ".config/quickshell/cloud-center/pages/AudioEditor.qml"
STAGED_TASK6_COMPONENTS = TASK6_STAGING / ".config/quickshell/cloud-center/components"
TASK7_STAGING = Path(__file__).resolve().parents[1] / ".superpowers/sdd/task7-staging"
STAGED_TASK7_PAGE = TASK7_STAGING / ".config/quickshell/cloud-center/pages/AudioEditor.qml"
STAGED_TASK7_COMPONENTS = TASK7_STAGING / ".config/quickshell/cloud-center/components"
STAGED_TASK7_BACKEND = TASK7_STAGING / ".config/quickshell/cloud-center/services/Backend.qml"
TASK8_STAGING = Path(__file__).resolve().parents[1] / ".superpowers/sdd/task8-staging"
UNIT = TASK8_STAGING / ".config/systemd/user/cloudyy-audio-autoswitch.service"
SETUP = TASK8_STAGING / "install/setup_services/setup-audio-autoswitch.sh"
INSTALL = TASK8_STAGING / "install/install.sh"
INSTALL_TEST = TASK8_STAGING / "install/test-install.sh"


class AudioPageContractTests(unittest.TestCase):
    def test_staged_user_service_runs_shared_python_entrypoint(self):
        unit = UNIT.read_text(encoding="utf-8")
        for fragment in (
            "Description=Cloudyy automatic audio output switching",
            "After=pipewire.service pipewire-pulse.service",
            "Type=simple",
            "WorkingDirectory=%h/cloudyy_scripts/cloud-center-v2",
            "ExecStart=/usr/bin/python3 -m lib.audio_autoswitch_service",
            "Restart=on-failure",
            "RestartSec=3",
            "TimeoutStopSec=5",
            "WantedBy=default.target",
        ):
            self.assertIn(fragment, unit)
        self.assertFalse(
            (UNIT.parent / "default.target.wants" / UNIT.name).exists(),
            "service activation must be owned by systemctl enable/disable",
        )

    def test_staged_audio_setup_is_idempotent_and_preserves_config(self):
        setup = SETUP.read_text(encoding="utf-8")
        for fragment in (
            "set -euo pipefail",
            'source "${INSTALL_DIR}/lib.sh"',
            '[[ -f "$UNIT_PATH" ]] ||',
            "command -v systemctl >/dev/null 2>&1 ||",
            "systemctl --user daemon-reload",
            'config = {"bluetooth_auto_switch": True, "enabled": False}',
            "json.loads(path.read_text(encoding=\"utf-8\"))",
            "except (OSError, json.JSONDecodeError):",
            'print("1" if config.get("bluetooth_auto_switch", True) or config.get("enabled", False) else "0")',
            'systemctl --user enable --now "$UNIT_NAME"',
            'systemctl --user disable --now "$UNIT_NAME"',
        ):
            self.assertIn(fragment, setup)
        self.assertNotIn("write_text", setup)
        self.assertNotIn("json.dump", setup)

    def test_staged_installer_runs_audio_setup_nonfatally(self):
        install = INSTALL.read_text(encoding="utf-8")
        quickshell = install.index("setup-quickshell-service.sh")
        audio_setup = install.index("setup_services/setup-audio-autoswitch.sh")
        self.assertLess(quickshell, audio_setup)
        self.assertIn(
            'bash "$audio_service_script" \\\n      || log_warn "Audio auto-switch service setup encountered issues (non-fatal)."',
            install,
        )

    def test_staged_installer_preflight_checks_audio_setup(self):
        installer_test = INSTALL_TEST.read_text(encoding="utf-8")
        for fragment in (
            "Audio service setup exists",
            "Audio service setup executable",
            "Audio service setup syntax valid",
            "Audio service setup uses strict mode",
            "./setup_services/setup-audio-autoswitch.sh",
        ):
            self.assertIn(fragment, installer_test)

    def test_model_routes_audio_to_native_page(self):
        self.assertEqual(model.NATIVE_KIND_OVERRIDES.get("__audio__"), "audio")
        shell = SHELL.read_text(encoding="utf-8")
        self.assertIn('page.kind === "audio" ? audioComponent', shell)
        self.assertIn("AudioEditor { page: pageLoader.page }", shell)

    def test_backend_forwards_all_audio_events(self):
        source = BACKEND.read_text(encoding="utf-8")
        for name in (
            "audioSnapshotEvent",
            "audioActionDoneEvent",
            "audioServiceStatusEvent",
        ):
            self.assertIn(name, source)
        for event in (
            'case "audio_snapshot"',
            'case "audio_action_done"',
            'case "audio_service_status"',
        ):
            self.assertIn(event, source)
        for fragment in (
            "function request(method, params, callback, errorCallback)",
            "function normalizeError(error)",
            "pending[id] = { success: callback, error: errorCallback }",
            "typeof errorCallback === \"function\"",
            "typeof entry === \"function\"",
            "typeof entry.error === \"function\"",
        ):
            self.assertIn(fragment, source)

    def test_native_page_uses_audio_snapshot_lifecycle_and_events(self):
        source = PAGE.read_text(encoding="utf-8")
        panel = PANEL.read_text(encoding="utf-8")
        for method in (
            "get_audio_snapshot",
            "start_audio_watch",
            "stop_audio_watch",
            "run_audio_action",
        ):
            self.assertIn(method, source)
        for signal in (
            "onAudioSnapshotEvent",
            "onAudioActionDoneEvent",
            "onAudioServiceStatusEvent",
        ):
            self.assertIn(signal, source)
        for fragment in (
            "function allocateGeneration()",
            "function handleActionReply(actionId, result)",
            "function handleActionError(actionId, error)",
            "function rejectAction(actionId, staleTarget, message)",
            "generation: actionGeneration",
            "Number(generation) !== Number(meta.generation)",
            "actions[String(actionId)] = true",
            "delete actions[String(actionId)]",
        ):
            self.assertIn(fragment, source)
        for fragment in (
            "volumeRow.editedTargetId",
            "volumeRow.editedTargetKind",
            "pendingKeyFor(volumeRow.editedTargetKind, volumeRow.editedTargetId, \"volume\")",
        ):
            self.assertIn(fragment, panel)

    def test_staged_page_correlates_rejections_and_debounced_targets(self):
        source = STAGED_PAGE.read_text(encoding="utf-8")
        panel = STAGED_PANEL.read_text(encoding="utf-8")
        for fragment in (
            "function allocateGeneration()",
            "function handleActionReply(actionId, result)",
            "function rejectAction(actionId, staleTarget, message)",
            "function setBusyTarget(target, actionId)",
            "function clearBusyTarget(target, actionId)",
            "function(result) { audioPage.handleActionReply(actionId, result); }",
            "function(error) { audioPage.handleActionError(actionId, error); }",
            "function handleActionError(actionId, error)",
            "generation: actionGeneration",
            "actions[String(actionId)] = true",
            "delete actions[String(actionId)]",
        ):
            self.assertIn(fragment, source)
        for fragment in (
            "volumeRow.editedTargetId",
            "volumeRow.editedTargetKind",
            "pendingKeyFor(volumeRow.editedTargetKind, volumeRow.editedTargetId, \"volume\")",
        ):
            self.assertIn(fragment, panel)

    def test_staged_finish_action_rejects_mismatched_completion_before_cleanup(self):
        source = STAGED_PAGE.read_text(encoding="utf-8")
        body = source[source.index("function finishAction("):source.index("function applyServiceStatus(")]
        guard = """if (meta === undefined
            || String(target) !== String(meta.target)
            || Number(generation) !== Number(meta.generation)) return;"""
        self.assertIn(guard, body)
        self.assertLess(body.index(guard), body.index("AudioState.clearCompleted"))
        self.assertLess(body.index(guard), body.index("clearBusyTarget"))
        self.assertLess(body.index(guard), body.index("delete nextMeta[id]"))

    def test_staged_backend_preserves_success_callbacks_and_routes_errors(self):
        source = STAGED_BACKEND.read_text(encoding="utf-8")
        for fragment in (
            "function request(method, params, callback, errorCallback)",
            "function normalizeError(error)",
            "pending[id] = { success: callback, error: errorCallback }",
            "typeof errorCallback === \"function\"",
            "typeof entry === \"function\"",
            "typeof entry.success === \"function\"",
            "typeof entry.error === \"function\"",
        ):
            self.assertIn(fragment, source)
        page = STAGED_PAGE.read_text(encoding="utf-8")
        self.assertIn("function handleActionError(actionId, error)", page)
        self.assertIn("function(error) { audioPage.handleActionError(actionId, error); }", page)

    def test_page_includes_applications_and_hardware(self):
        source = PAGE.read_text(encoding="utf-8")
        for fragment in (
            "AudioApplicationRow",
            "AudioHardwareRow",
            'text: "Applications"',
            'text: "Hardware"',
            'text: "No active playback streams"',
            'text: "No audio cards found"',
            "hardwareExpanded",
            "automationExpanded",
        ):
            self.assertIn(fragment, source)

    def test_device_selection_applies_default_immediately(self):
        panel = PANEL.read_text(encoding="utf-8")
        self.assertNotIn("Make default", panel)
        self.assertIn('panel.actionRequested(panel.actionFor("default")', panel)
        self.assertIn("panel.selected(name)", panel)

    def test_stream_and_card_actions_are_fixed(self):
        apps = (COMPONENTS / "AudioApplicationRow.qml").read_text(encoding="utf-8")
        hardware = (COMPONENTS / "AudioHardwareRow.qml").read_text(encoding="utf-8")
        for action in ("set_stream_volume", "set_stream_mute", "move_stream"):
            self.assertIn(action, apps)
        self.assertIn("set_card_profile", hardware)

    def test_staged_task_six_rows_preserve_pending_values_and_stable_targets(self):
        apps = (STAGED_TASK6_COMPONENTS / "AudioApplicationRow.qml").read_text(encoding="utf-8")
        hardware = (STAGED_TASK6_COMPONENTS / "AudioHardwareRow.qml").read_text(encoding="utf-8")
        page = STAGED_TASK6_PAGE.read_text(encoding="utf-8")
        for fragment in (
            "String(root.stream.index)",
            '"stream:" + volumeRow.editedTargetId + ":volume"',
            '"stream:" + root.stream.index + ":muted"',
            '"stream:" + root.stream.index + ":sink_name"',
            "AudioState.displayValue",
            "editedTargetId",
            "editedTargetKind",
        ):
            self.assertIn(fragment, apps)
        for fragment in (
            "profile_descriptions",
            '"card:" + root.card.name + ":active_profile"',
            "AudioState.displayValue",
        ):
            self.assertIn(fragment, hardware)
        self.assertIn('action !== "set_stream_volume"', page)
        self.assertIn('action !== "set_stream_mute"', page)

    def test_staged_automation_ui_owns_service_migration(self):
        source = STAGED_TASK7_PAGE.read_text(encoding="utf-8")
        for fragment in (
            "AudioPriorityEditor",
            "CloudDialog",
            'request("enable_audio_autoswitch_service"',
            "AudioState.shouldPromptService(snapshot)",
            "servicePromptHandled",
            "function handleServiceRequestError(error)",
        ):
            self.assertIn(fragment, source)

    def test_staged_priority_editor_uses_fixed_backend_configuration_methods(self):
        source = (STAGED_TASK7_COMPONENTS / "AudioPriorityEditor.qml").read_text(
            encoding="utf-8"
        )
        for fragment in (
            'request("set_audio_automation"',
            'request("set_audio_priority"',
            "priority.concat",
            "priority.slice",
            "signal updated(var snapshot)",
            "signal error(string message)",
            "function serviceWanted()",
        ):
            self.assertIn(fragment, source)

    def test_priority_editor_uses_saved_and_live_labels(self):
        source = (COMPONENTS / "AudioPriorityEditor.qml").read_text(encoding="utf-8")
        self.assertIn("output_priority_labels", source)
        self.assertIn("function priorityLabel(name)", source)
        self.assertIn("(disconnected)", source)
        self.assertNotIn("(offline)", source)

    def test_device_panel_uses_friendly_state_labels(self):
        panel = PANEL.read_text(encoding="utf-8")
        self.assertIn("function friendlyState(state)", panel)
        self.assertIn('"Not in use"', panel)
        self.assertIn('"In use"', panel)

    def test_staged_priority_editor_restores_toggle_bindings_after_requests(self):
        source = (STAGED_TASK7_COMPONENTS / "AudioPriorityEditor.qml").read_text(
            encoding="utf-8"
        )
        for fragment in (
            "property var automationPending: ({})",
            "function setAutomationPending(key, pending)",
            "function restoreAutomationBinding(key)",
            "Qt.binding(function() { return root.bluetoothEnabled; })",
            "Qt.binding(function() { return root.wiredEnabled; })",
            'if (isAutomationPending(key)) return;',
            "setAutomationPending(key, true)",
            "setAutomationPending(key, false)",
            "finishAutomation(key, result)",
            "finishAutomationError(key, reason)",
            'enabled: !root.isAutomationPending("bluetooth_auto_switch")',
            'enabled: !root.isAutomationPending("enabled")',
        ):
            self.assertIn(fragment, source)

        set_automation = source[
            source.index("function setAutomation(key, value)"):
            source.index("function setPriority(next)")
        ]
        self.assertLess(
            set_automation.index("restoreAutomationBinding(key);"),
            set_automation.index('S.Backend.request("set_audio_automation"'),
        )
        self.assertIn("const desired = checked;", source)

    def test_staged_backend_exit_detaches_pending_before_notifying_opt_in_errors(self):
        source = STAGED_TASK7_BACKEND.read_text(encoding="utf-8")
        exit_body = source[source.index("onExited: (code, status) => {"):]
        for fragment in (
            "const detachedPending = backend.pending;",
            "backend.pending = ({});",
            "const exitError = backend.normalizeError({",
            'error: "backend-exited",',
            "for (const id in detachedPending)",
            'typeof entry !== "function" && typeof entry.error === "function"',
            "try { entry.error(exitError); } catch (error) {",
            'console.warn("ccd exit error callback failed:", error);',
        ):
            self.assertIn(fragment, exit_body)

        self.assertLess(
            exit_body.index("const detachedPending = backend.pending;"),
            exit_body.index("backend.pending = ({});"),
        )
        self.assertLess(
            exit_body.index("backend.pending = ({});"),
            exit_body.index("for (const id in detachedPending)"),
        )
        self.assertLess(
            exit_body.index("for (const id in detachedPending)"),
            exit_body.index("backend.crashCount++;"),
        )
