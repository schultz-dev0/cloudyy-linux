import QtQuick
import QtTest
import "../../../../.config/quickshell/overview/services/AppIdentity.js" as AppIdentity

TestCase {
    name: "AppIdentity"

    readonly property var cursorDesktop: ({
        id: "cursor",
        name: "Cursor",
        wmclass: "Cursor",
        exec: "/usr/share/cursor/cursor %F",
        desktopPath: "/usr/share/applications/cursor.desktop",
        icon: "co.anysphere.cursor"
    })

    function cursorIde(title, history) {
        return {
            address: `0x${history}`,
            class: "Cursor",
            initialClass: "cursor",
            title: title,
            initialTitle: "Cursor",
            focusHistoryID: history
        };
    }

    function cursorAgents(history) {
        return {
            address: `0xa${history}`,
            class: "Cursor",
            initialClass: "cursor",
            title: "Agents",
            initialTitle: "Agents",
            focusHistoryID: history
        };
    }

    function test_cursor_roles_are_separate() {
        const ide = AppIdentity.identityForWindow(cursorIde("cloudyy-linux — Cursor", 3), cursorDesktop);
        const agents = AppIdentity.identityForWindow(cursorAgents(1), cursorDesktop);
        compare(AppIdentity.canonicalKey(ide), "cursor::main");
        compare(AppIdentity.canonicalKey(agents), "cursor::agents");
        compare(AppIdentity.displayLabel(ide), "Cursor");
        compare(AppIdentity.displayLabel(agents), "Cursor Agents");
    }

    function test_desktop_request_is_always_primary() {
        const requested = AppIdentity.primaryIdentityForApp(cursorDesktop);
        compare(AppIdentity.canonicalKey(requested), "cursor::main");
    }

    function test_primary_filter_excludes_more_recent_agents() {
        const requested = AppIdentity.primaryIdentityForApp(cursorDesktop);
        const ide = cursorIde("cloudyy-linux — Cursor", 4);
        const matches = AppIdentity.filterWindowsForIdentity(
            requested, [cursorAgents(0), ide], cursorDesktop);
        compare(matches.length, 1);
        compare(matches[0].address, ide.address);
    }

    function test_same_role_windows_group_in_focus_order() {
        const requested = AppIdentity.primaryIdentityForApp(cursorDesktop);
        const first = cursorIde("one — Cursor", 7);
        const second = cursorIde("two — Cursor", 2);
        const matches = AppIdentity.filterWindowsForIdentity(
            requested, [first, second], cursorDesktop);
        compare(matches.length, 2);
        compare(matches[0].address, second.address);
    }

    function test_process_identity_separates_same_class_apps() {
        const alpha = AppIdentity.identityForWindow({
            class: "Collision", processAppKey: "alpha", title: "Alpha"
        }, null);
        const beta = AppIdentity.identityForWindow({
            class: "Collision", processAppKey: "beta", title: "Beta"
        }, null);
        verify(!AppIdentity.sameIdentity(alpha, beta));
    }

    function test_resolved_desktop_identity_beats_process_basename() {
        const identity = AppIdentity.identityForWindow({
            class: "dev.zed.Zed", processAppKey: "zeditor", title: "project"
        }, {
            id: "dev.zed.Zed", name: "Zed", wmclass: "dev.zed.Zed"
        });
        compare(AppIdentity.canonicalKey(identity), "dev.zed.zed::main");
    }

    function test_unresolved_desktop_class_uses_process_identity() {
        const identity = AppIdentity.identityForWindow({
            class: "Collision", processAppKey: "alpha", title: "Alpha"
        }, {
            resolved: false, id: "", name: "Collision", wmclass: "Collision"
        });
        compare(AppIdentity.canonicalKey(identity), "alpha::main");
    }

    function test_confirmed_same_class_collision_prefers_process_identity() {
        const desktop = {
            id: "collision", name: "Collision", wmclass: "Collision"
        };
        const alpha = AppIdentity.identityForWindow({
            class: "Collision", processAppKey: "alpha",
            forceProcessIdentity: true, title: "Alpha"
        }, desktop);
        const beta = AppIdentity.identityForWindow({
            class: "Collision", processAppKey: "beta",
            forceProcessIdentity: true, title: "Beta"
        }, desktop);
        verify(!AppIdentity.sameIdentity(alpha, beta));
    }

    function test_workspace_target_matches_title_basename() {
        const target = AppIdentity.workspaceTargetForWindow(
            cursorIde("cloudyy-linux — Cursor", 0),
            ["file:///home/user/cloudyy-linux", "file:///home/user/other"]
        );
        compare(target.kind, "folderUri");
        compare(target.value, "file:///home/user/cloudyy-linux");
    }

    function test_workspace_target_ignores_malformed_uri() {
        compare(AppIdentity.workspaceTargetForWindow(
            cursorIde("project — Cursor", 0), ["file:///%E0%A4%A"]), null);
    }

    function test_legacy_cursor_pin_migrates_to_main() {
        const pin = AppIdentity.normalizePin(
            { class: "cursor", icon: "co.anysphere.cursor" },
            cursorDesktop, null, []);
        compare(pin.version, 2);
        compare(pin.role, "main");
        compare(AppIdentity.pinKey(pin), "cursor::main");
    }

    function test_main_and_agents_pins_can_coexist() {
        const main = AppIdentity.normalizePin({
            version: 2, appId: "cursor", class: "cursor", role: "main", label: "Cursor"
        }, cursorDesktop, null, []);
        const agents = AppIdentity.normalizePin({
            version: 2, appId: "cursor", class: "cursor", role: "agents", label: "Cursor Agents"
        }, cursorDesktop, null, []);
        verify(AppIdentity.pinKey(main) !== AppIdentity.pinKey(agents));
    }

    function test_desktop_id_uses_filename_without_final_suffix_data() {
        return [
            {
                tag: "user-local app",
                path: "/home/user/.local/share/applications/workpuls-agent.desktop",
                desktopId: "workpuls-agent"
            },
            {
                tag: "Firefox PWA",
                path: "/home/user/.local/share/applications/FFPWA-01KWFJA7Z4H5GH9KRP5Y31RG6J.desktop",
                desktopId: "FFPWA-01KWFJA7Z4H5GH9KRP5Y31RG6J"
            },
            {
                tag: "system app",
                path: "/usr/share/applications/obsidian.desktop",
                desktopId: "obsidian"
            },
            {
                tag: "desktop in identifier",
                path: "/usr/share/applications/org.telegram.desktop.desktop",
                desktopId: "org.telegram.desktop"
            }
        ];
    }

    function test_desktop_id_uses_filename_without_final_suffix(data) {
        compare(AppIdentity.desktopIdFromPath(data.path), data.desktopId);
    }

    function test_activation_focuses_main_not_agents() {
        const requested = AppIdentity.primaryIdentityForApp(cursorDesktop);
        const ide = cursorIde("cloudyy-linux — Cursor", 5);
        const decision = AppIdentity.activationDecision(
            requested, [cursorAgents(0), ide], cursorDesktop,
            ["file:///home/user/cloudyy-linux"]);
        compare(decision.action, "focus");
        compare(decision.window.address, ide.address);
    }

    function test_agents_only_launches_cursor_workspace() {
        const requested = AppIdentity.primaryIdentityForApp(cursorDesktop);
        const decision = AppIdentity.activationDecision(
            requested, [cursorAgents(0)], cursorDesktop,
            ["file:///home/user/cloudyy-linux"]);
        compare(decision.action, "launch");
        compare(decision.launchTarget.kind, "folderUri");
        compare(decision.launchTarget.value, "file:///home/user/cloudyy-linux");
        compare(decision.exec, "/usr/share/cursor/cursor");
        compare(AppIdentity.launchArguments(requested, decision.launchTarget), [
            "--classic", "/home/user/cloudyy-linux"
        ]);
    }

    function test_agents_role_has_distinct_glass_launch_flag() {
        const agents = AppIdentity.identityForWindow(cursorAgents(0), cursorDesktop);
        const decision = AppIdentity.activationDecision(agents, [], cursorDesktop, []);
        compare(decision.exec, "/usr/share/cursor/cursor");
        compare(AppIdentity.launchArguments(agents, null), ["--glass"]);
    }

    function test_empty_input_is_stable() {
        const identity = AppIdentity.identityForWindow({}, null);
        compare(AppIdentity.canonicalKey(identity), "unknown::main");
        verify(AppIdentity.sameIdentity(identity, AppIdentity.identityForWindow({}, null)));
    }
}
