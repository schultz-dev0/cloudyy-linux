import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def text(path: str) -> str:
    return (ROOT / path).read_text()


def qml_blocks(source: str, declaration: str) -> list[str]:
    """Return balanced QML object blocks beginning with declaration."""
    blocks = []
    needle = f"{declaration} {{"
    cursor = 0
    while (start := source.find(needle, cursor)) != -1:
        depth = 0
        for end in range(start + len(declaration), len(source)):
            if source[end] == "{":
                depth += 1
            elif source[end] == "}":
                depth -= 1
                if depth == 0:
                    blocks.append(source[start:end + 1])
                    break
        cursor = start + len(needle)
    return blocks


def lua_call_blocks(source: str, call: str) -> list[str]:
    """Return complete balanced Lua calls, ignoring parentheses in strings."""
    blocks = []
    needle = f"{call}("
    cursor = 0
    while (start := source.find(needle, cursor)) != -1:
        depth = 0
        quote = None
        escaped = False
        for end in range(start + len(call), len(source)):
            char = source[end]
            if quote is not None:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == quote:
                    quote = None
            elif char in ('"', "'"):
                quote = char
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    blocks.append(source[start:end + 1])
                    cursor = end + 1
                    break
        else:
            cursor = start + len(needle)
    return blocks


def test_island_state_and_pages_are_registered():
    qmldir = text(".config/quickshell/modules/island/qmldir")
    assert "singleton IslandState 1.0 IslandState.qml" in qmldir
    assert "IslandNavigationState 1.0 IslandNavigationState.qml" in qmldir
    for component in (
        "IslandCarousel", "IslandPageFrame", "IslandInlineActivity",
        "NotificationsPage", "MediaPage",
        "SystemOverviewPage",
    ):
        assert f"{component} 1.0 {component}.qml" in qmldir
    # Calendar and Timer deliberately have no island page — see
    # test_calendar_is_a_standalone_panel_not_an_island_page and
    # test_removed_timer_surfaces_are_not_registered_or_present.
    for component in ("CalendarPage", "TimerPage"):
        assert f"{component} 1.0 {component}.qml" not in qmldir


def test_island_carousel_keeps_dynamic_registry_delegates_alive():
    carousel = text(".config/quickshell/modules/island/IslandCarousel.qml")
    assert "required property var registry" in carousel
    assert "required property var navigationState" in carousel
    assert "function _syncPages()" in carousel
    assert "if (root._samePageStructure(nextPages))" in carousel
    assert "model: root._pages" in carousel
    assert "model: QuickIsland.IslandIntegrationRegistry.availablePages" not in carousel
    assert "Repeater {" in carousel
    assert "delegate: Loader {" in carousel
    assert "sourceComponent: modelData.pageComponent" in carousel
    assert "active: true" in carousel
    assert "visible: root.isPageNear(index)" in carousel
    assert "layer.enabled: true" in carousel
    for component in (
        "NotificationsPage", "MediaPage",
        "AgentsPage", "SystemOverviewPage",
    ):
        assert f"QuickIsland.{component} {{" not in carousel


def test_dynamic_island_injects_real_carousel_dependencies():
    island = text(".config/quickshell/modules/island/DynamicIsland.qml")
    carousel = island.split("QuickIsland.IslandCarousel {", 1)[1].split("}", 1)[0]
    assert "registry: QuickIsland.IslandIntegrationRegistry" in carousel
    assert "navigationState: QuickIsland.IslandState" in carousel


def test_injectable_navigation_model_is_the_single_state_implementation():
    wrapper = text(".config/quickshell/modules/island/IslandState.qml")
    model = text(".config/quickshell/modules/island/IslandNavigationState.qml")
    assert "QuickIsland.IslandNavigationState {" in wrapper
    assert "registry: QuickIsland.IslandIntegrationRegistry" in wrapper
    assert "required property var registry" in model
    assert "function _repairNavigation()" in model
    assert "QuickIsland.IslandIntegrationRegistry" not in model


def test_island_state_uses_registry_navigation_and_rejects_empty_opening():
    state = text(".config/quickshell/modules/island/IslandNavigationState.qml")
    assert "state.registry.availablePageIds" in state
    assert "state.registry.integrations" in state
    assert "function restorePersistentSnapshot(snapshot)" in state
    for function_name in ("pin", "show", "showPage", "cycle"):
        body = state.split(f"function {function_name}(", 1)[1].split("\n    }", 1)[0]
        assert "return false;" in body
    assert "function onRevisionChanged()" in state
    assert "state._repairNavigation();" in state


def test_carousel_disables_cycling_controls_for_fewer_than_two_pages():
    carousel = text(".config/quickshell/modules/island/IslandCarousel.qml")
    assert "readonly property int pageCount: pageOrder.length" in carousel
    assert "enabled: root.pageCount > 1" in carousel
    assert "visible: root.pageCount > 1" in carousel
    assert "root.pageCount < 2" in carousel
    wheel = carousel.split("WheelHandler {", 1)[1].split("HoverHandler {", 1)[0]
    assert "root.pageCount > 1" in wheel


def test_transient_activity_disables_persistent_input_and_focus():
    shell = text(".config/quickshell/modules/island/DynamicIsland.qml")
    carousel = text(".config/quickshell/modules/island/IslandCarousel.qml")
    persistent = shell.split("id: persistentContent", 1)[1].split(
        "Loader {", 1
    )[0]
    assert "enabled: !island.transientActive" in persistent
    assert "focus: root.enabled && root.navigationState.keyboardRequested" in carousel


# test_timer_compact_page_falls_back_to_newest_paused_timer removed: it
# tested modules/island/TimerPage.qml, which no longer exists at all — see
# test_removed_timer_surfaces_are_not_registered_or_present. The "which
# timer to show" fallback logic it used to verify now lives only in the
# resting pill (activeRestingSummary / IslandIntegrationRegistryModel.qml's
# "timer" entry, restingSummary: countdown ? {...} : null).


def test_removed_timer_surfaces_are_not_registered_or_present():
    """Timer has no island page at all anymore — not even a display-only
    one. It only ever surfaces via the resting pill (see
    test_dynamic_resting_content_uses_registry_summary_without_timer_surface
    for that; the name there predates this change but the file it guards
    against — a dedicated TimerRestingPill.qml — is the same kind of thing
    this test guards against for the full page). Command Center (Trigger >
    Timer) owns all creation/pause/reset/stop control.
    """
    qmldir = text(".config/quickshell/modules/timer/qmldir")
    assert qmldir == "module QuickTimer\nsingleton TimerService 1.0 TimerService.qml\n"
    for component in ("TimerPanel", "TimerBarPill", "TimerContent", "TimerCard", "NewTimerForm"):
        assert f"{component} 1.0 {component}.qml" not in qmldir
        assert not (ROOT / f".config/quickshell/modules/timer/{component}.qml").exists()

    island_qmldir = text(".config/quickshell/modules/island/qmldir")
    assert "TimerPage 1.0 TimerPage.qml" not in island_qmldir
    assert not (ROOT / ".config/quickshell/modules/island/TimerPage.qml").exists()

    registry = text(".config/quickshell/modules/island/IslandIntegrationRegistry.qml")
    assert "QuickIsland.TimerPage {}" not in registry
    assert "timerPageComponent" not in registry

    model = text(".config/quickshell/modules/island/IslandIntegrationRegistryModel.qml")
    assert "timerPageComponent" not in model
    timer_entry = model.split('id: "timer",', 1)[1].split("},", 1)[0]
    assert "pageComponent: null," in timer_entry


def test_timer_service_exposes_provider_adapter_contract():
    service = text(".config/quickshell/modules/timer/TimerService.qml")
    for token in (
        "property bool loaded: false",
        "readonly property bool busy:",
        'property string providerError: ""',
        "readonly property ListModel timers: ListModel {}",
        "readonly property int runningCount:",
        "readonly property var nearestCountdown:",
        "readonly property var primaryTimer:",
        "signal timerCompleted(var timer)",
        "function refresh()",
        "function createCountdown(label, durationSeconds)",
        "function startStopwatch(label)",
        "function pause(timerId, mode)",
        "function resume(timerId)",
        "function reset(timerId, mode)",
        "function rename(timerId, label)",
        "function remove(timerId)",
        "function stop(timerId)",
    ):
        assert token in service
    assert '["cloudyy-timer", "list", "--json"]' in service
    assert "TimerProviderPolicy.js" in service


def test_timer_service_watches_provider_state_and_reconciles_command_failures():
    service = text(".config/quickshell/modules/timer/TimerService.qml")
    assert 'path: root.stateDir + "/state.json"' in service
    assert "watchChanges: true" in service
    assert "onFileChanged: root.refresh()" in service
    command_exit = service.split("id: commandProc", 1)[1].split("Component.onCompleted", 1)[0]
    assert "root.refresh();" in command_exit
    assert "exitCode === 0 && exitStatus === 0" in command_exit
    assert "root.providerError =" in command_exit
    assert "property var _commandQueue: []" in service
    assert "function _startNextCommand()" in service
    assert "listProc.running || commandProc.running" in service
    assert "root._commandQueue = root._commandQueue.concat([command]);" in service


def test_timer_service_has_no_qml_owned_persistence_or_ticking_model_mutation():
    service = text(".config/quickshell/modules/timer/TimerService.qml")
    for obsolete in (
        "active.json",
        "_scheduleSave",
        "_saveNow",
        "_serializeTimers",
        "_restoreTimers",
        "saveProc",
        "timer_log.sh",
        'setProperty(i, "elapsedSeconds"',
        'setProperty(idx, "elapsedSeconds"',
    ):
        assert obsolete not in service
    assert "property int presentationEpoch:" in service
    assert "interval: 1000" in service


# test_timer_content_is_continuous_and_keyboard_accessible removed: it
# tested TimerContent/TimerCard/NewTimerForm.qml, which no longer exist —
# see test_removed_timer_surfaces_are_not_registered_or_present.


# test_timer_page_is_display_only removed: it briefly existed to verify a
# display-only (no buttons) island Timer page, but that whole page is gone
# now too — see test_removed_timer_surfaces_are_not_registered_or_present.


def test_timer_stop_routes_through_supported_cli():
    service = text(".config/quickshell/modules/timer/TimerService.qml")
    mgmt = text(".config/quickshell/modules/commandcenter/scripts/timer-mgmt.sh")
    assert '["cloudyy-timer", "stop", timerId, "--json"]' in service
    assert 'cloudyy-timer stop "$id" --json' in mgmt
    assert "TimerService.complete(" not in mgmt


def test_timer_completion_uses_standard_notifications_without_custom_qml_paths():
    shell = text(".config/quickshell/shell.qml")
    qmldir = text(".config/quickshell/modules/island/qmldir")
    assert not (
        ROOT / ".config/quickshell/modules/island/TimerIslandContent.qml"
    ).exists()
    assert not (ROOT / ".config/quickshell/modules/timer/timer_log.sh").exists()
    assert "TimerIslandContent" not in qmldir
    assert "TimerIslandContent" not in shell
    assert "onTimerCompleted" not in shell
    assert 'import "modules/timer" as QuickTimer' not in shell
    assert "NotificationServer {" in shell
    assert "QuickNotifPanel.NotifPanelService.track(notif);" in shell
    assert "QuickIsland.DynamicIslandService.push({" in shell


def test_timer_snapshot_replacement_prepares_focus_before_model_clear():
    service = text(".config/quickshell/modules/timer/TimerService.qml")
    replacement = service.split("function _replaceTimers(nextTimers, completedTimers)", 1)[1].split(
        "function refresh()", 1
    )[0]
    assert "root.timerAboutToRemove(" in replacement
    assert "root.timers.clear();" in replacement
    assert "if (!nextById[current.timerId] && completedById[current.timerId])" in replacement
    assert replacement.index("root.timerAboutToRemove(") < replacement.index(
        "root.timers.clear();"
    )


# test_timer_removal_focus_recovery_is_guarded_and_deterministic and
# test_compact_timer_completion_recovers_pause_and_reset_focus removed: both
# tested keyboard-focus recovery across the compact pause/reset/stop buttons
# and expanded TimerContent, none of which exist anymore — see
# test_removed_timer_surfaces_are_not_registered_or_present.

# test_timer_history_refresh_tracks_month_without_qml_log_writer removed: it
# tested TimerContent.qml's history view, which no longer exists.


def test_carousel_wheel_uses_dominant_pixel_axis():
    carousel = text(".config/quickshell/modules/island/IslandCarousel.qml")
    assert carousel.count("WheelHandler {") == 1
    assert "enabled: root.pageCount > 1 && !root.navigationState.expanded" in carousel
    assert (
        "acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad"
        in carousel
    )
    assert "const pixelX = event.pixelDelta.x;" in carousel
    assert "const pixelY = event.pixelDelta.y;" in carousel
    assert "Math.abs(pixelX) > Math.abs(pixelY)" in carousel
    assert "root.trackpadDelta += pixelX;" in carousel
    assert "root.trackpadDelta = 0;" in carousel


def test_expanded_carousel_does_not_capture_plain_horizontal_arrows():
    carousel = text(".config/quickshell/modules/island/IslandCarousel.qml")
    left = carousel.split("Keys.onLeftPressed:", 1)[1].split(
        "Keys.onRightPressed:", 1
    )[0]
    right = carousel.split("Keys.onRightPressed:", 1)[1].split(
        "Keys.onReturnPressed:", 1
    )[0]
    for handler in (left, right):
        assert "root.navigationState.expanded || root.pageCount < 2" in handler
        assert handler.index("root.navigationState.expanded") < handler.index(
            "root.navigationState.cycle("
        )


def test_carousel_return_and_numpad_enter_activate_the_current_page():
    carousel = text(".config/quickshell/modules/island/IslandCarousel.qml")
    assert carousel.count("Keys.onEnterPressed:") == 1
    return_handler = carousel.split("Keys.onReturnPressed:", 1)[1].split(
        "Keys.onEnterPressed:", 1
    )[0]
    enter_handler = carousel.split("Keys.onEnterPressed:", 1)[1].split(
        "Keys.onEscapePressed:", 1
    )[0]
    for handler in (return_handler, enter_handler):
        assert "root.navigationState.activateCurrent();" in handler
        assert "event.accepted = true;" in handler


def test_calendar_is_a_standalone_panel_not_an_island_page():
    """Calendar was deliberately un-cut-over: its own top-center overlay,
    opened from the bar clock and SUPER+CTRL+C, not an island carousel page.
    """
    qmldir = text(".config/quickshell/modules/calendar/qmldir")
    assert "CalendarContent 1.0 CalendarContent.qml" in qmldir
    assert "CalendarMiniSection 1.0 CalendarMiniSection.qml" in qmldir
    assert "CalendarPanel 1.0 CalendarPanel.qml" in qmldir
    assert "singleton CalendarPanelService 1.0 CalendarPanelService.qml" in qmldir
    assert (ROOT / ".config/quickshell/modules/calendar/CalendarPanel.qml").exists()
    assert not (ROOT / ".config/quickshell/modules/island/CalendarPage.qml").exists()


def test_calendar_service_reports_save_failure_without_rollback():
    service = text(".config/quickshell/modules/calendar/CalendarService.qml")
    assert 'property string persistenceError: ""' in service
    assert "signal persistenceFailed(string message)" in service
    assert "onExited: (exitCode, exitStatus) =>" in service
    assert "root.persistenceFailed(root.persistenceError);" in service
    assert "root.events =" not in service.split(
        "onExited: (exitCode, exitStatus) =>", 1
    )[1]


def test_calendar_service_coalesces_overlapping_saves_without_stopping_process():
    service = text(".config/quickshell/modules/calendar/CalendarService.qml")
    save_flow = service.split("function save()", 1)[1].split(
        "// ── Processes", 1
    )[0]
    assert "property bool _saveInFlight: false" in service
    assert 'property string _pendingSavePayload: ""' in service
    assert "if (root._saveInFlight)" in save_flow
    assert "root._pendingSavePayload = payload;" in save_flow
    assert "saveProc.running = false" not in save_flow
    assert "function _startSave(payload)" in save_flow
    exit_flow = service.split("onExited: (exitCode, exitStatus) =>", 1)[1]
    assert "const pending = root._pendingSavePayload;" in exit_flow
    assert "if (pending)" in exit_flow
    assert "root._startSave(pending);" in exit_flow


def test_calendar_grid_has_complete_keyboard_day_navigation():
    grid = text(".config/quickshell/modules/calendar/CalendarGrid.qml")
    for token in (
        "activeFocusOnTab: true",
        "Keys.onLeftPressed:",
        "Keys.onRightPressed:",
        "Keys.onUpPressed:",
        "Keys.onDownPressed:",
        "Keys.onReturnPressed:",
        "root._moveKeyboardDate(-7)",
        "root._moveKeyboardDate(7)",
    ):
        assert token in grid


def test_calendar_nested_controls_restore_focus_and_escape():
    content = text(".config/quickshell/modules/calendar/CalendarContent.qml")
    card = text(".config/quickshell/modules/calendar/CalendarEventCard.qml")
    dialog = text(".config/quickshell/modules/calendar/CalendarEventDialog.qml")
    for token in (
        "function focusInitial()",
        "signal closeNestedRequested",
        "function _restoreFocus()",
        "CalendarEventDialog {",
    ):
        assert token in content
    assert "Keys.onReturnPressed:" in card
    assert "Keys.onEscapePressed:" in card
    assert "Keys.onTabPressed:" in dialog
    assert "Keys.onBacktabPressed:" in dialog


def test_calendar_content_is_continuous_and_event_rows_are_not_cards():
    content = text(".config/quickshell/modules/calendar/CalendarContent.qml")
    card = text(".config/quickshell/modules/calendar/CalendarEventCard.qml")
    body = content.split("CalendarEventDialog {", 1)[0]
    event_row = card.split("// ── Context menu", 1)[0]
    assert 'text: "󰃭  Calendar"' not in body
    assert "id: calendarBody" in body
    assert "id: bodyDivider" in body
    assert "radius: root.sectionRadius" not in body
    assert "Theme.surface_container" not in body
    assert card.lstrip().startswith("pragma ComponentBehavior: Bound")
    assert "\nItem {\n    id: root" in card
    assert "Theme.surface_container_high" not in event_row
    assert "id: rowRule" in event_row
    assert "color: root.activeFocus ? Theme.islandFocus : Theme.islandBorder" in event_row


def test_calendar_event_delete_restores_a_deterministic_agenda_focus():
    day_view = text(".config/quickshell/modules/calendar/CalendarDayView.qml")
    assert "function focusInitial()" in day_view
    assert "eventRepeater.itemAt(0)" in day_view
    assert "Qt.callLater(() => root.focusInitial());" in day_view
    assert "addButton.forceActiveFocus();" in day_view


def test_calendar_event_pointer_activation_matches_keyboard_menu_access():
    card = text(".config/quickshell/modules/calendar/CalendarEventCard.qml")
    row_pointer = card.split("acceptedButtons:", 1)[1].split(
        "// ── Context menu", 1
    )[0]
    assert "Qt.LeftButton | Qt.RightButton" in row_pointer
    assert "root._openMenu()" in row_pointer
    assert "enabled: !ctxMenu.visible" in row_pointer


def test_calendar_event_menu_stacks_above_shared_dismiss_layer():
    card = text(".config/quickshell/modules/calendar/CalendarEventCard.qml")
    assert "id: menuDismissLayer" in card
    menu = card.split("id: ctxMenu", 1)[1].split(
        "id: menuDismissLayer", 1
    )[0]
    dismiss = card.split("id: menuDismissLayer", 1)[1]
    shared_parent = "parent: root.parent ? root.parent : root"
    assert shared_parent in menu
    assert shared_parent in dismiss
    assert "root.mapToItem(parent," in menu
    assert "z: 20" in menu
    assert "z: 19" in dismiss
    assert "onClicked: ctxMenu.close()" in dismiss


def test_calendar_panel_hosts_content_with_exclusive_keyboard_focus():
    """on_demand only grants focus on a click; opening via keybind needs
    Exclusive or arrow/enter/escape navigation inside CalendarContent never
    receives input (see the same fix already applied to DynamicIsland.qml).
    """
    panel = text(".config/quickshell/modules/calendar/CalendarPanel.qml")
    assert "QuickCalendar.CalendarContent {" in panel
    assert "WlrKeyboardFocus.Exclusive" in panel
    assert "WlrKeyboardFocus.OnDemand" not in panel
    assert "calendarContent.focusInitial()" in panel
    assert 'IpcHandler {\n        target: "calendar"' in panel


def test_unified_island_ipc_replaces_standalone_handlers():
    """Catch duplicate, incomplete, or misrouted island IPC ownership."""
    shell = text(".config/quickshell/shell.qml")
    island_handlers = [
        block for block in qml_blocks(shell, "IpcHandler")
        if 'target: "island"' in block
    ]
    assert len(island_handlers) == 1
    handler = island_handlers[0]
    signatures = {
        name: re.sub(r"\s+", " ", arguments.strip())
        for name, arguments in re.findall(
            r"function\s+(\w+)\s*\(([^)]*)\)(?:\s*:\s*\w+)?", handler
        )
    }
    assert signatures == {
        "toggle": "",
        "show": "",
        "hide": "",
        "page": "id: string",
    }
    for call in (
        "QuickIsland.IslandState.toggle(",
        "QuickIsland.IslandState.show(",
        "QuickIsland.IslandState.hide()",
        "QuickIsland.IslandState.showPage(id,",
    ):
        assert call in handler
    for target in ('target: "calculator"', 'target: "calendar"', 'target: "timer"'):
        assert target not in shell


def test_unified_island_ipc_routes_opening_calls_to_focused_monitor():
    """Catch opening IPC calls using an empty, stale, or unrelated screen name."""
    shell = text(".config/quickshell/shell.qml")
    handler = next(
        block for block in qml_blocks(shell, "IpcHandler")
        if 'target: "island"' in block
    )
    focused_screen = 'Hyprland.focusedMonitor?.name ?? ""'
    wrong_routes = []
    for name in ("toggle", "show", "page"):
        match = re.search(
            rf"function\s+{name}\s*\([^)]*\)(?:\s*:\s*\w+)?\s*{{([^}}]*)}}",
            handler,
        )
        if match is None or match.group(1).count(focused_screen) != 1:
            wrong_routes.append(name)
    assert wrong_routes == []


def test_external_activation_runtime_contract():
    """Catch failure hiding the island or success leaving it pinned."""
    result = subprocess.run(
        [
            "timeout", "15s", "qs", "--no-color", "-p",
            ".config/quickshell/IslandStateRuntimeTest.qml",
        ],
        cwd=ROOT,
        env={**os.environ, "QT_QPA_PLATFORM": os.environ.get(
            "QT_QPA_PLATFORM", "offscreen")},
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "TASK10_ISLAND_STATE_FAIL" not in output, output
    assert "TASK10_ISLAND_STATE_PASS" in output, output


def test_shell_does_not_own_replaced_standalone_island_surfaces():
    """Catch legacy windows/state surviving the island cutover. Calendar is
    deliberately NOT part of this cutover (see
    test_calendar_is_a_standalone_panel_not_an_island_page) — its own
    top-level import/instantiation in shell.qml is expected and correct.
    """
    shell = text(".config/quickshell/shell.qml")
    for token in (
        'import "modules/calculator" as QuickCalculator',
        "property bool calendarOpen",
        "property bool calculatorOpen",
        "QuickCalculator.Calculator {",
        "QuickTimer.TimerPanel {",
    ):
        assert token not in shell
    assert 'import "modules/calendar" as QuickCalendar' in shell
    assert "QuickCalendar.CalendarPanel {" in shell


def test_bar_routes_calendar_through_its_own_panel_without_obsolete_controls():
    """Catch the old bell/timer controls returning. The clock deliberately
    opens the standalone CalendarPanel (see
    test_calendar_is_a_standalone_panel_not_an_island_page), not an island
    page — the dead IslandState.showPage("calendar", ...) call this used to
    make is exactly the bug that made the calendar unopenable.
    """
    bar = text(".config/quickshell/Bar.qml")
    assert 'import "modules/timer" as QuickTimer' not in bar
    assert "QuickTimer.TimerBarPill {" not in bar
    assert "id: notifBell" not in bar
    assert 'import "modules/calendar" as QuickCalendar' in bar
    clock = next(
        block for block in qml_blocks(bar, "Item") if "id: clockPill" in block
    )
    assert "QuickCalendar.CalendarPanelService.toggle()" in clock
    assert 'QuickIsland.IslandState.showPage("calendar",' not in bar


def test_bar_left_owns_workspaces_and_center_reserve_prevents_overlap():
    """Catch a centered workspace row or bar content overlapping the island."""
    bar = text(".config/quickshell/Bar.qml")
    left_row = next(
        block for block in qml_blocks(bar, "Row") if "id: leftRow" in block
    )
    assert bar.count("id: wsRow") == 1
    assert "id: wsRow" in left_row
    assert left_row.index("id: wsRow") > left_row.index('label: "󰅟"')

    reserve = next(
        block for block in qml_blocks(bar, "Item") if "id: islandReserve" in block
    )
    left_zone = next(
        block for block in qml_blocks(bar, "Item") if "id: leftZone" in block
    )
    right_zone = next(
        block for block in qml_blocks(bar, "Item") if "id: rightZone" in block
    )
    assert "width: 200" in reserve
    assert "right: islandReserve.left" in left_zone
    assert "left: islandReserve.right" in right_zone
    assert "clip: true" in left_zone
    assert "clip: true" in right_zone


def test_focused_workspace_uses_keyline_without_vertical_displacement():
    """Catch focused workspace icons or labels jumping vertically again."""
    bar = text(".config/quickshell/Bar.qml")
    assert "anchors.verticalCenterOffset: focused ? -2 : 0" not in bar
    keyline = next(
        block for block in qml_blocks(bar, "Rectangle")
        if "id: workspaceKeyline" in block
    )
    assert "height: 2" in keyline
    assert "visible: focused" in keyline


def test_spotlight_keeps_calculator_and_currency_backends():
    spotlight = text(".config/quickshell/modules/spotlight/Spotlight.qml")
    assert (ROOT / ".config/quickshell/modules/calculator/backend/Calculator.qml").is_file()
    assert (ROOT / ".config/quickshell/modules/calculator/backend/CalculatorMath.js").is_file()
    assert (ROOT / ".config/quickshell/modules/currency/backend/CurrencyConverter.qml").is_file()
    assert (ROOT / ".config/quickshell/modules/currency/backend/CurrencyParse.js").is_file()
    assert 'import "../calculator/backend" as CalcBackend' in spotlight
    assert 'import "../currency/backend" as CurrencyBackend' in spotlight


def test_spotlight_currency_retention_requires_matching_expression():
    """Stale currency rows must not survive a query change (reopen flake)."""
    service = text(".config/quickshell/modules/spotlight/SpotlightService.qml")
    assert "r.type !== \"calculator\" && r.type !== \"currency\" && r.type !== \"time\"" in service
    assert '(r.expression ?? "") === query' in service
    # Old bug: currency kept unconditionally after the calc/time check.
    assert "return true;\n        });" not in service.split("function applySearchResults", 1)[1].split("function closeSubPanels", 1)[0]


def test_currency_parse_skips_uk_slang_quid():
    parse_js = text(".config/quickshell/modules/currency/backend/CurrencyParse.js")
    assert '"quid"' not in parse_js.lower()
    assert "dollars" in parse_js
    assert "euros" in parse_js


def test_removed_qml_surfaces_and_obsolete_references_do_not_survive():
    """Catch deleted calculator/media UI or stale standalone references returning."""
    removed = (
        ".config/quickshell/modules/calculator/Calculator.qml",
        ".config/quickshell/modules/controlcenter/tiles/CalculatorTile.qml",
        ".config/quickshell/modules/island/MediaActivity.qml",
    )
    for path in removed:
        assert not (ROOT / path).exists()

    # CalendarPanel/"ipc call calendar" are deliberately NOT obsolete — see
    # test_calendar_is_a_standalone_panel_not_an_island_page.
    obsolete = re.compile(
        r"TimerPanel|TimerBarPill|CalculatorTile|QuickCalculator|"
        r"calculatorOpen|calendarOpen|ipc call (?:calculator|timer)\b"
    )
    roots = (
        ".config/quickshell",
        ".config/hypr",
        "install/assets/defaults/hypr",
    )
    matches = []
    for root in roots:
        for path in (ROOT / root).rglob("*"):
            if path.is_file() and obsolete.search(path.read_text(errors="ignore")):
                matches.append(str(path.relative_to(ROOT)))
    assert matches == []


def test_control_center_removes_only_calculator_tile_from_retained_content():
    """Catch Calculator wiring lingering or retained panel sections being removed."""
    panel = text(".config/quickshell/NotifPanel.qml")
    for token in ("CalculatorTile {", "calculatorOpen", "calculatorToggle"):
        assert token not in panel
    for token in (
        "DndTile {", "WifiBluetoothTile {", "DarkModeTile {",
        "NightLightTile {", "SystemTile {", "MediaCard {",
        "CalendarMiniSection {", "id: notifStack",
    ):
        assert token in panel


def test_live_and_default_bindings_expose_two_island_toggle_shortcuts():
    """Two deliberate island-toggle binds (SHIFT+Space and apostrophe, see
    the "pull out and focus the island" keybind request) both dispatch the
    same qs ipc call island toggle — not a split/duplicated island field.
    Calendar's own SUPER+CTRL+C bind is deliberately allowed (see
    test_calendar_is_a_standalone_panel_not_an_island_page).
    """
    paths = (
        ".config/hypr/bindings.lua",
        "install/assets/defaults/hypr/bindings.lua",
    )
    for path in paths:
        bindings = text(path)
        island_blocks = [
            block for block in lua_call_blocks(bindings, "hl.bind")
            if re.search(r"\b(?:qs|quickshell) ipc call island\b", block)
        ]
        assert len(island_blocks) == 2
        keys = {
            re.search(r'mainMod \.\. " \+ ([^"]+)"', block).group(1)
            for block in island_blocks
        }
        assert keys == {"SHIFT + Space", "apostrophe"}
        for island in island_blocks:
            assert island.count(
                'hl.dsp.exec_cmd("qs ipc call island toggle")'
            ) == 1
        assert re.search(r"ipc call (?:calculator|timer)\b", bindings) is None


def test_task_11_preserves_adjacent_live_and_default_bindings():
    """Catch unrelated command, overview, notification, or window binds being removed."""
    expected = (
        (
            'mainMod .. " + K"',
            'hl.dsp.exec_cmd("quickshell ipc call spotlight toggle")',
            'desc = "Open spotlight search"',
        ),
        (
            'mainMod .. " + Tab"',
            'hl.dsp.exec_cmd("quickshell ipc call overview open")',
            'desc = "Show all workspaces (hold Super, keep pressing Tab to cycle)"',
        ),
        (
            'mainMod .. " + Space"',
            'hl.dsp.exec_cmd("qs ipc call spotlight command")',
            'desc = "Command Center"',
        ),
        (
            'mainMod .. " + N"',
            'hl.dsp.exec_cmd("qs ipc call notifs toggle")',
            'desc = "Toggle notif center"',
        ),
        (
            'mainMod .. " + CTRL + M"',
            'hl.dsp.exec_cmd("qs ipc call system toggle")',
            'desc = "Toggle system stats overlay"',
        ),
        (
            '"ALT + Tab"',
            "hl.dsp.window.cycle_next()",
            'desc = "Cycle windows"',
        ),
    )
    paths = (
        ".config/hypr/bindings.lua",
        "install/assets/defaults/hypr/bindings.lua",
    )
    for path in paths:
        blocks = lua_call_blocks(text(path), "hl.bind")
        for key, dispatcher, description in expected:
            matches = [
                block for block in blocks
                if key in block and dispatcher in block and description in block
            ]
            assert len(matches) == 1, f"{path}: missing preserved bind for {key}"


def test_live_and_default_rules_remove_obsolete_layers_and_disable_island_blur():
    """Catch stale utility layers, island blur, or lost retained panel rules."""
    paths = (
        ".config/hypr/windowrules.lua",
        "install/assets/defaults/hypr/windowrules.lua",
    )
    for path in paths:
        rules = text(path)
        for obsolete in ("calculator", "calendar", "timer"):
            assert f"quickshell_{obsolete}" not in rules
            assert f"quickshell:{obsolete}" not in rules
        for retained in ("control", "system"):
            assert rules.count(f'name = "quickshell_{retained}"') == 1
            assert rules.count(f'namespace = "^(quickshell:{retained})$"') == 1
        island = rules.split('name = "quickshell_island"', 1)[1].split("})", 1)[0]
        assert "blur = false" in island
        assert "ignore_alpha" not in island


def test_task_11_preserves_unrelated_live_and_default_layer_rules():
    """Catch unrelated Quickshell layer-rule blocks being removed or overwritten."""
    expected = (
        ("quickshell_command", "^(quickshell:command)$"),
        ("quickshell_overview", "^(quickshell:overview)$"),
        ("quickshell_dock", "^(quickshell:dock)$"),
        ("quickshell_notifications", "^(quickshell:notifications)$"),
        ("quickshell_sliders", "^(quickshell:sliders)$"),
    )
    paths = (
        ".config/hypr/windowrules.lua",
        "install/assets/defaults/hypr/windowrules.lua",
    )
    for path in paths:
        blocks = lua_call_blocks(text(path), "hl.layer_rule")
        for name, namespace in expected:
            matches = [
                block for block in blocks if f'name = "{name}"' in block
            ]
            assert len(matches) == 1, f"{path}: missing layer rule {name}"
            block = matches[0]
            assert f'namespace = "{namespace}"' in block
            assert "blur = true" in block
            assert "ignore_alpha = 0.2" in block


def test_island_theme_has_persistent_shell_visual_tokens():
    theme = text(".config/quickshell/Theme.qml")
    for token in (
        "islandRestWidth: 176", "islandRestHeight: 24",
        "islandCarouselWidth: 610", "islandCarouselHeight: 142",
        "islandExpandedMaxHeight: 536", "islandShoulderRadius: 0",
        "islandRestLowerRadius: 12", "islandOpenLowerRadius: 26",
    ):
        assert token in theme


def test_island_shape_uses_native_per_corner_radii():
    shape = text(".config/quickshell/modules/island/IslandPillShape.qml")
    assert "Rectangle {" in shape
    assert qml_blocks(shape, "ShapePath") == []
    assert "topLeftRadius: root.shoulder" in shape
    assert "topRightRadius: root.shoulder" in shape
    assert "bottomLeftRadius: root.lower" in shape
    assert "bottomRightRadius: root.lower" in shape


def test_island_window_masks_transparent_shape_cutouts():
    shell = text(".config/quickshell/modules/island/DynamicIsland.qml")
    assert "mask: Region {" in shell
    assert "shape: RegionShape.Ellipse" in shell
    assert "Theme.islandShoulderRadius" in shell
    assert "island.effectiveLowerRadius" in shell


def test_island_mask_and_paint_share_effective_lower_radius():
    shell = text(".config/quickshell/modules/island/DynamicIsland.qml")
    assert (
        "readonly property real effectiveLowerRadius: Math.min(\n"
        "        lowerRadius, width / 2, height / 2)"
    ) in shell
    mask = shell.split("mask: Region {", 1)[1].split("WlrLayershell.layer", 1)[0]
    assert "island.lowerRadius" not in mask
    assert mask.count("island.effectiveLowerRadius") >= 10
    assert shell.count("lowerRadius: island.effectiveLowerRadius") == 2


def test_preview_height_observer_is_declarative_and_non_accumulating():
    shell = text(".config/quickshell/modules/island/DynamicIsland.qml")
    assert "target: contentLoader.item" in shell
    assert "ignoreUnknownSignals: true" in shell
    assert "function onPreviewHeightChanged()" in shell
    assert "previewHeightChanged.connect" not in shell


def test_notification_service_exposes_live_object_state_and_actions():
    service = text(
        ".config/quickshell/modules/notifpanel/NotifPanelService.qml"
    )
    for token in (
        "property var latestNotification: null",
        "readonly property int unreadCount:",
        "signal notificationAdded(var notification)",
        "function markAllRead()",
        "function invokeAction(notification, actionId)",
        "latestNotification = notif;",
        "notificationAdded(notif);",
        "notification.actions",
        "action.invoke();",
    ):
        assert token in service
    assert "JSON.stringify" not in service


def test_notification_unread_state_tracks_close_and_control_center_open():
    service = text(
        ".config/quickshell/modules/notifpanel/NotifPanelService.qml"
    )
    panel = text(".config/quickshell/NotifPanel.qml")
    assert "property var _unreadIds:" in service
    assert "notif.closed.connect" in service
    assert "delete unreadIds[String(notif.id)]" in service
    assert "_unreadIds = ({});" in service
    assert "QuickNotifPanel.NotifPanelService.markAllRead();" in panel


def test_dnd_tracks_before_suppressing_notification_presentation():
    shell = text(".config/quickshell/shell.qml")
    notification_flow = shell.split("onNotification: notif => {", 1)[1].split(
        "        }\n    }", 1
    )[0]
    track = "QuickNotifPanel.NotifPanelService.track(notif);"
    dnd = "if (root.dnd)"
    assert notification_flow.index(track) < notification_flow.index(dnd)
    dnd_branch = notification_flow.split(dnd, 1)[1].split(
        "if (notif.lastGeneration)", 1
    )[0]
    assert "return;" in dnd_branch
    assert "expire()" not in dnd_branch
    assert notification_flow.index(dnd) < notification_flow.index(
        "QuickIsland.DynamicIslandService.playNotifSound();"
    )


def test_compact_notifications_use_service_objects_and_delegate_opening():
    page = text(".config/quickshell/modules/island/NotificationsPage.qml")
    carousel = text(".config/quickshell/modules/island/IslandCarousel.qml")
    registry = text(".config/quickshell/modules/island/IslandIntegrationRegistry.qml")
    shell = text(".config/quickshell/shell.qml")
    for token in (
        "QuickNotifPanel.NotifPanelService.latestNotification",
        "QuickNotifPanel.NotifPanelService.unreadCount",
        '"All clear"',
        "model: root.compactActions",
        "QuickNotifPanel.NotifPanelService.invokeAction(",
        "onTapped: root.activateRequested()",
    ):
        assert token in page
    assert "QuickIsland.NotificationsPage {}" in registry
    assert "target: pageLoader.item" in carousel
    assert "function onActivateRequested()" in carousel
    assert "root.navigationState.activateCurrent();" in carousel
    assert "function onControlCenterRequested()" in shell
    delegation = shell.split("function onControlCenterRequested()", 1)[1].split(
        "}", 1
    )[0]
    assert "root.notifOpen = true;" in delegation
    assert (
        'QuickIsland.IslandState.completeExternalActivation("controlCenter", '
        "root.notifOpen);"
    ) in delegation


def test_inline_notification_fields_keep_live_objects_inert():
    inline = text(
        ".config/quickshell/modules/island/IslandInlineActivity.qml"
    )
    assert "property var notification: null" in inline
    assert "readonly property var actions:" in inline
    assert "notification.actions" in inline
    assert "invokeAction(" not in inline


def test_latest_notification_falls_back_to_newest_live_object():
    service = text(
        ".config/quickshell/modules/notifpanel/NotifPanelService.qml"
    )
    assert "property var _notifications: []" in service
    assert "const remaining = service._notifications.filter" in service
    assert "service._notifications = remaining;" in service
    assert "service.latestNotification = remaining.length" in service


def test_compact_action_taps_do_not_also_activate_control_center():
    page = text(".config/quickshell/modules/island/NotificationsPage.qml")
    right_content = page.split("rightContent: Item {", 1)[1]
    assert "onTapped: root.activateRequested()" not in right_content


def test_notification_server_advertises_action_capability():
    shell = text(".config/quickshell/shell.qml")
    server = shell.split("NotificationServer {", 1)[1].split(
        "onNotification: notif => {", 1
    )[0]
    assert "actionsSupported: true" in server


def test_compact_notifications_limit_live_action_references_to_two():
    page = text(".config/quickshell/modules/island/NotificationsPage.qml")
    assert "readonly property var compactActions:" in page
    assert "Math.min(actions.length, 2)" in page
    assert "compactActions.push(actions[i]);" in page
    assert "model: root.compactActions" in page
    assert "JSON.stringify" not in page
    assert ".map(" not in page


def test_system_monitor_exposes_truthful_snapshot_availability_and_uptime():
    service = text(
        ".config/quickshell/modules/systemmonitor/SystemMonitorService.qml"
    )
    for token in (
        "property bool hasSnapshot: false",
        "property bool cpuAvailable: false",
        "property bool ramAvailable: false",
        "property bool temperatureAvailable: false",
        "property bool gpuMetricAvailable: false",
        "property int uptimeSeconds: 0",
        "readonly property string uptimeLabel:",
        'path: "/proc/uptime"',
    ):
        assert token in service
    assert "cpuAvailable = isNumber(cpu.percent)" in service
    assert "ramAvailable = isNumber(ram.percent)" in service
    assert "temperatureAvailable = isNumber(cpu.temp_c) && cpu.temp_c > 0" in service
    assert "gpuMetricAvailable = gpuAvailable && isNumber(gpu.percent)" in service
    assert "hasSnapshot = true" in service


def test_system_snapshot_failure_invalidates_metrics_and_times_out_by_generation():
    service = text(
        ".config/quickshell/modules/systemmonitor/SystemMonitorService.qml"
    )
    ingest = service.split("function ingestLine(line)", 1)[1].split(
        "function markSnapshotUnavailable", 1
    )[0]
    timeout = service.split("id: snapshotTimeout", 1)[1].split(
        "readonly property FileView", 1
    )[0]
    for token in (
        "function markSnapshotUnavailable()",
        "cpuAvailable = false",
        "ramAvailable = false",
        "temperatureAvailable = false",
        "gpuMetricAvailable = false",
        "property int _snapshotGeneration: 0",
        "property int _timedOutSnapshotGeneration: 0",
        "snapshotTimeout.restart()",
    ):
        assert token in service
    assert "markSnapshotUnavailable();" in ingest
    assert "snapshotProc.signal(15);" in timeout
    assert "root._activeSnapshotGeneration" in timeout
    stream = service.split("id: snapshotOut", 1)[1].split("onExited:", 1)[0]
    assert "root._timedOutSnapshotGeneration" in stream
    assert "root.ingestLine(text);" in stream
    restart = service.split("function restartMonitor()", 1)[1].split(
        "function shellQuote", 1
    )[0]
    assert "stale = false" not in restart


def test_system_page_is_compact_and_renders_only_approved_detail():
    page = text(".config/quickshell/modules/island/SystemOverviewPage.qml")
    for token in (
        "root.service.cpuAvailable",
        "root.service.ramAvailable",
        "root.service.gpuMetricAvailable",
        "root.service.uptimeLabel",
        "root.service.temperatureAvailable",
        'label: "CPU"',
        'label: "RAM"',
        'label: "GPU"',
        'text: "UPTIME"',
        'text: "TEMP"',
    ):
        assert token in page
    assert "QuickIsland.IslandState.expanded" not in page
    assert "expandedContent" not in page
    assert "Loader {" not in page


def test_media_page_keeps_player_and_no_player_states_compact_and_accessible():
    page = text(".config/quickshell/modules/island/MediaPage.qml")
    for token in (
        "QuickIsland.MprisFocus.activePlayer",
        '"No player active"',
        "root.player.trackArtUrl",
        "root.player.trackTitle",
        "root.player.trackArtist",
        "root.player.position",
        "root.player.length",
        "root.player.previous()",
        "root.player.togglePlaying()",
        "root.player.next()",
        "activeFocusOnTab: root.controlsActive",
        "Keys.onReturnPressed:",
        "Keys.onEnterPressed:",
        "id: artwork",
        "visible: artwork.status === Image.Ready",
        "visible: artwork.status !== Image.Ready",
    ):
        assert token in page
    assert "expandedContent" not in page
    assert "Loader {" not in page
    assert "playerctl" not in page


def test_audited_island_runtime_regressions_are_wired():
    service = text(".config/quickshell/modules/island/DynamicIslandService.qml")
    state = text(".config/quickshell/modules/island/IslandNavigationState.qml")
    island = text(".config/quickshell/modules/island/DynamicIsland.qml")
    carousel = text(".config/quickshell/modules/island/IslandCarousel.qml")
    shell = text(".config/quickshell/shell.qml")
    media = text(".config/quickshell/modules/island/MediaPage.qml")
    resting = text(".config/quickshell/modules/island/IslandRestingPill.qml")

    assert "property bool recordingStarting: false" in service
    assert "exec hyprcap" in service
    assert "kill -0" in service
    assert "function _cancelRecordingLaunch()" in service
    assert "launchSerial !== root._recordingLaunchSerial" in service
    assert "root._recordingStartWaitProc" in service
    assert 'pkill -TERM -P \\"$pid\\"' in service
    assert 'grep -qx \'RECORDING=1\'' in shell

    pin = state.split("function pin(screenName)", 1)[1].split("function toggle", 1)[0]
    assert "if (screenName)" in pin
    assert "openingScreenName = screenName;" in pin
    escape = state.split("function handleEscape()", 1)[1]
    assert 'if (target === "resting")' in escape
    assert "hide();" in escape
    assert "signal closingRequested" in state
    assert "DynamicIslandService.clearAllNotifications();" in island

    assert "Math.abs(to - from) > viewport.width * 1.5" in carousel
    assert shell.count("screen: root.externalPanelScreen ?? root.islandScreen") == 2
    assert shell.count("root.externalPanelScreen = root.islandScreen;") == 2
    assert shell.count("root.externalPanelScreen = null;") == 2

    assert "readonly property real currentPosition:" in media
    assert "root.currentPosition / root.player.length" in media
    assert "root.formatTime(root.currentPosition)" in media
    assert "RowLayout {" in resting
    assert "Layout.fillWidth: true" in resting


def test_mpris_focus_keeps_the_first_playing_player_and_clears_when_empty():
    focus = text(".config/quickshell/modules/island/MprisFocus.qml")
    assert (
        "if (!playing && p.playbackState === MprisPlaybackState.Playing)"
        in focus
    )
    assert "players.length > 0 ? players[0] : null" in focus
    assert "root.activePlayer = root.pick();" in focus


def test_system_activation_uses_retained_panel_handshake():
    shell = text(".config/quickshell/shell.qml")
    request = shell.split("function onSystemOverviewRequested()", 1)[1].split(
        "    }\n\n    //", 1
    )[0]
    assert "QuickSystemMonitor.SystemMonitorService.open = true;" in request
    assert "try {" in request
    assert "catch (error)" in request
    assert "Qt.callLater(() =>" in request
    assert request.count("QuickIsland.IslandState.completeExternalActivation(") == 2
    assert '"systemOverview", false' in request
    assert '"systemOverview", opened' in request
    assert "QuickSystemMonitor.SystemMonitorService.open" in request


def test_retained_system_panel_refresh_uses_existing_daemon_api():
    panel = text(
        ".config/quickshell/modules/systemmonitor/SystemOverviewPanel.qml"
    )
    assert "onClicked: svc.ensureDaemon()" in panel
    assert "ensureMonitor()" not in panel


def test_transient_service_exposes_explicit_lifecycle_and_urgent_hold():
    service = text(".config/quickshell/modules/island/DynamicIslandService.qml")
    for token in (
        "signal transientPresented(var activity)",
        "signal transientUpdated(var activity)",
        "signal transientFinished(string activityId)",
        "function holdCurrent(activityId)",
        "function resumeCurrent(activityId)",
        "root.transientPresented(root.currentActivity);",
        "root.transientUpdated(act);",
        "root.transientFinished(activityId);",
    ):
        assert token in service


def test_dynamic_island_restores_exact_persistent_state_after_full_transient():
    shell = text(".config/quickshell/modules/island/DynamicIsland.qml")
    for token in (
        "property var persistentSnapshot: null",
        "mode: QuickIsland.IslandState.mode",
        "currentPage: QuickIsland.IslandState.currentPage",
        "rememberedPage: QuickIsland.IslandState.rememberedPage",
        "openingScreenName: QuickIsland.IslandState.openingScreenName",
        "QuickIsland.IslandState.restorePersistentSnapshot(snapshot);",
        "function onTransientPresented(activity)",
        "function onTransientFinished(activityId)",
    ):
        assert token in shell
    restore = shell.split("function _restorePersistentState()", 1)[1].split(
        "function _syncTransientPresentation()", 1
    )[0]
    assert "IslandState.currentPage = snapshot.currentPage" not in restore


def test_dynamic_resting_content_uses_registry_summary_without_timer_surface():
    island = text(".config/quickshell/modules/island/DynamicIsland.qml")
    qmldir = text(".config/quickshell/modules/island/qmldir")
    assert "QuickIsland.IslandRestingPill {" in island
    assert "summary: QuickIsland.IslandIntegrationRegistry.activeRestingSummary" in island
    assert 'opacity: QuickIsland.IslandState.mode === "resting" ? 1 : 0' in island
    assert 'activeRestingSummary?.kind === "neutral"' in island
    assert "TimerRestingPill" not in island
    assert "TimerRestingPill" not in qmldir
    assert not (
        ROOT / ".config/quickshell/modules/island/TimerRestingPill.qml"
    ).exists()


def test_pinned_notifications_use_non_resizing_inline_strip():
    shell = text(".config/quickshell/modules/island/DynamicIsland.qml")
    carousel = text(".config/quickshell/modules/island/IslandCarousel.qml")
    assert "Policy.transientPresentation" in shell
    assert "inlineActivity: island.inlineNotification" in shell
    viewport = carousel.split("id: viewport", 1)[1].split("Row {", 1)[0]
    assert "root.inlineActivity ?" not in viewport
    assert "bottomMargin: 14" in viewport


def test_inline_notification_geometry_uses_persistent_mode_dimensions():
    shell = text(".config/quickshell/modules/island/DynamicIsland.qml")
    assert 'readonly property bool transientActive: transientPresentation === "full"' in shell
    assert "readonly property real targetWidth: transientActive" in shell
    assert "? Theme.islandShellWidth : persistentWidth" in shell
    assert "readonly property real targetHeight: transientActive" in shell
    assert "? transientHeight : persistentHeight" in shell
    theme = text(".config/quickshell/Theme.qml")
    assert "islandCarouselWidth: 610" in theme
    assert "islandCarouselHeight: 142" in theme
    assert "islandExpandedMaxHeight: 536" in theme


def test_switching_a_full_notification_inline_discards_the_old_snapshot():
    shell = text(".config/quickshell/modules/island/DynamicIsland.qml")
    sync = shell.split("function _syncTransientPresentation()", 1)[1].split(
        "function _applyActivityToLoader()", 1
    )[0]
    inline_branch = sync.split("} else", 1)[1]
    assert "island.persistentSnapshot = null;" in inline_branch


def test_preview_screen_ownership_combines_drag_pin_and_persistent_owner():
    shell = text(".config/quickshell/shell.qml")
    island_screen = shell.split("readonly property var islandScreen:", 1)[1].split(
        "Connections {", 1
    )[0]
    assert "QuickIsland.IslandState.openingScreenName" in island_screen
    assert "root.islandScreenPin" in island_screen
    drag_connection = shell.split("function onPreviewDragActiveChanged()", 1)[1].split(
        "function barIpcEnabled", 1
    )[0]
    assert "root.islandScreenPin = root.islandScreen;" in drag_connection


def test_live_preview_drag_cannot_be_preempted_by_a_new_activity():
    service = text(".config/quickshell/modules/island/DynamicIslandService.qml")
    push_flow = service.split("function push(activityDef)", 1)[1].split(
        "function remove(id)", 1
    )[0]
    drag_guard = push_flow.split("if (root.previewDragActive)", 1)[1].split(
        "if (root.currentActivity === null)", 1
    )[0]
    assert "root._insertQueued(activity);" in drag_guard
    assert "return id;" in drag_guard


def test_activity_text_uses_jetbrains_and_native_rendering():
    for name in (
        "NotificationActivity.qml", "OsdBurstActivity.qml",
        "ScreenshotActivity.qml", "RecordingActivity.qml",
        "RecordPickerActivity.qml", "IslandInlineActivity.qml",
    ):
        source = text(f".config/quickshell/modules/island/{name}")
        assert 'font.family: "sans-serif"' not in source
        assert source.count("Text {") == source.count("renderType: Text.NativeRendering")


def test_transient_loader_waits_for_the_matching_component_properties():
    shell = text(".config/quickshell/modules/island/DynamicIsland.qml")
    injection = shell.split("function _applyActivityToLoader()", 1)[1]
    for activity_type, destination in (
        ("screenshot", "imagePath"),
        ("recording", "videoPath"),
        ("recordPicker", "activityId"),
        ("osd", "kind"),
        ("timer", "completedTimer"),
    ):
        branch = injection.split(
            f'if (data.activityType === "{activity_type}")', 1
        )[1].split("return;", 1)[0]
        assert f"item.{destination} === undefined" in branch


def test_urgent_transients_are_held_independent_of_presentation_mode():
    shell = text(".config/quickshell/modules/island/DynamicIsland.qml")
    sync = shell.split("function _syncTransientPresentation()", 1)[1].split(
        "function _applyActivityToLoader()", 1
    )[0]
    assert (
        "        }\n"
        "        if ((activity.data?.urgency ?? 0) === 2)"
    ) in sync
    urgent = sync.split("if ((activity.data?.urgency", 1)[1]
    assert "holdCurrent(activity.id)" in urgent
    assert "resumeCurrent(activity.id)" in urgent


def test_queued_same_kind_osd_is_updated_without_duplicate_or_reordering():
    service = text(".config/quickshell/modules/island/DynamicIslandService.qml")
    osd = service.split("function showOsdBurst", 1)[1].split(
        "property string _recordingOutFile", 1
    )[0]
    for token in (
        "function _queuedOsd(kind)",
        "const queued = root._queuedOsd(kind);",
        "queued.data.icon = icon;",
        "queued.data.valueLabel = valueLabel;",
        "queued.data.progress = prog;",
        "root._osdBurstId = queued.id;",
        "return queued.id;",
    ):
        assert token in service
    queued_branch = osd.split("const queued = root._queuedOsd(kind);", 1)[1].split(
        "root._osdBurstId = root.push", 1
    )[0]
    assert "root._insertQueued" not in queued_branch
    assert "root.pendingCount" not in queued_branch


def test_same_kind_osd_update_revives_dismissing_activity():
    service = text(".config/quickshell/modules/island/DynamicIslandService.qml")
    shell = text(".config/quickshell/modules/island/DynamicIsland.qml")
    osd = service.split("function showOsdBurst", 1)[1].split(
        "property string _recordingOutFile", 1
    )[0]
    assert "Policy.shouldReviveOsd" in osd
    assert 'root._finishingActivityId = "";' in osd
    updated = shell.split("function onTransientUpdated(activity)", 1)[1].split(
        "function onTransientFinished", 1
    )[0]
    assert "dismissTimer.stop();" in updated
    assert "island.transientDismissing = false;" in updated
    assert "island._syncTransientPresentation();" in updated


def test_loader_injection_requires_ready_matching_component_identity():
    shell = text(".config/quickshell/modules/island/DynamicIsland.qml")
    assert "function _expectedActivityComponent(activity)" in shell
    expected = shell.split("function _expectedActivityComponent(activity)", 1)[1].split(
        "function _applyActivityToLoader()", 1
    )[0]
    assert "activity?.contentComponent ?? notificationActivityComponent" in expected
    assert "property var loadedSourceComponent: null" in shell
    injection = shell.split("function _applyActivityToLoader()", 1)[1]
    guard = injection.split("const data", 1)[0]
    assert "contentLoader.status !== Loader.Ready" in guard
    assert "contentLoader.sourceComponent !== expectedComponent" in guard
    assert "contentLoader.loadedSourceComponent !== expectedComponent" in guard
    loader = shell.split("id: contentLoader", 1)[1].split("HoverHandler", 1)[0]
    assert "onSourceComponentChanged: loadedSourceComponent = null" in loader
    assert "onLoaded:" in loader
    assert "loadedSourceComponent = sourceComponent;" in loader


# ── Task 12 visual defect contracts ──────────────────────────────────────────


def test_island_window_ignores_bar_exclusive_zone_without_zone_override():
    """Catch the island being pushed below the bar's reserved area.

    ExclusionMode.Ignore maps to layer-shell exclusive zone -1, which places
    the overlay island at the physical top edge. Any explicit exclusiveZone
    assignment flips Quickshell back to ExclusionMode.Normal with that zone,
    so the bar's reserved area pushes the island down and opens a top gap.
    """
    shell = text(".config/quickshell/modules/island/DynamicIsland.qml")
    assert "exclusionMode: ExclusionMode.Ignore" in shell
    assert not re.search(r"^\s*exclusiveZone\s*:", shell, re.MULTILINE)


def test_island_pill_border_follows_native_rounded_rectangle():
    shape = text(".config/quickshell/modules/island/IslandPillShape.qml")
    assert "border.width: root.strokeWidth" in shape
    assert "border.color: root.strokeColor" in shape
    assert qml_blocks(shape, "PathArc") == []


def test_island_page_frame_forces_injected_content_to_fill_slots():
    """Catch page content collapsing into zero-sized wrapper items.

    Pages inject an unsized wrapper Item into each slot via the data aliases.
    Unless the frame forces injected children to fill the slot, every
    parent-anchored layout inside pages collapses to the slot origin: content
    piles at the top and right-slot content centers on the divider.
    """
    frame = text(".config/quickshell/modules/island/IslandPageFrame.qml")
    assert "function _fillSlot(" in frame
    assert "anchors.fill = slot;" in frame
    assert frame.count("onChildrenChanged: root._fillSlot(") >= 2


def test_bar_workspace_row_aligns_with_pills_and_keyline_clears_icon():
    """Catch the focused-workspace keyline clipping through the icon.

    Bar pills sit at y=0 of the row with height barHeight - pillPadV * 2.
    Centering the workspace row against the taller leftRow drops the icons,
    and bottom-anchoring the keyline inside an icon-sized cell overlaps the
    icon. The delegate needs an icon cell matching pill height with the
    keyline below it.
    """
    bar = text(".config/quickshell/Bar.qml")
    ws_row = next(
        block for block in qml_blocks(bar, "Row")
        if "id: wsRow" in block and "id: leftRow" not in block
    )
    ws_row_header = ws_row.split("Repeater {", 1)[0]
    assert "anchors.verticalCenter" not in ws_row_header
    keyline = next(
        block for block in qml_blocks(bar, "Rectangle")
        if "id: workspaceKeyline" in block
    )
    assert "bottom: parent.bottom" in keyline
    assert "anchors.fill: parent" not in keyline
    icon_cell = next(
        block for block in qml_blocks(bar, "Item")
        if "id: workspaceIconCell" in block
    )
    assert "height: bar.barHeight - bar.pillPadV * 2" in icon_cell
    assert "top: parent.top" in icon_cell


def test_island_page_frame_runtime_geometry_fills_slots():
    """Catch runtime geometry regressions in slot content sizing."""
    result = subprocess.run(
        [
            "timeout", "15s", "qs", "--no-color", "-p",
            ".config/quickshell/IslandLayoutRuntimeTest.qml",
        ],
        cwd=ROOT,
        env={**os.environ, "QT_QPA_PLATFORM": os.environ.get(
            "QT_QPA_PLATFORM", "offscreen")},
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "TASK12_ISLAND_LAYOUT_FAIL" not in output, output
    assert "TASK12_ISLAND_LAYOUT_PASS" in output, output


# ── Dynamic integration registry contracts ───────────────────────────────────


def test_registry_is_registered_and_exposes_observable_contract():
    qmldir = text(".config/quickshell/modules/island/qmldir")
    registry = text(
        ".config/quickshell/modules/island/IslandIntegrationRegistry.qml"
    )
    assert "singleton IslandIntegrationRegistry 1.0 IslandIntegrationRegistry.qml" in qmldir
    assert "IslandIntegrationRegistryModel 1.0 IslandIntegrationRegistryModel.qml" in qmldir
    assert "IslandRestingPill 1.0 IslandRestingPill.qml" in qmldir
    for token in (
        "property alias integrations:",
        "property alias availablePages:",
        "property alias availablePageIds:",
        "property alias activeRestingSummary:",
        "property alias revision:",
        "property alias settingsError:",
        "function integrationById(id)",
        "function isPageAvailable(id)",
        "function reloadSettings()",
    ):
        assert token in registry


def test_registry_adapters_follow_provider_backed_page_and_resting_semantics():
    registry = text(
        ".config/quickshell/modules/island/IslandIntegrationRegistry.qml"
    )
    model = text(
        ".config/quickshell/modules/island/IslandIntegrationRegistryModel.qml"
    )
    for adapter_id in ("notifications", "timer", "media", "agents"):
        assert f'id: "{adapter_id}"' in model
    for component in (
        "NotificationsPage", "MediaPage", "AgentsPage"
    ):
        assert f"{component} {{" in registry
    assert "TimerPage {" not in registry

    for binding in (
        "notificationService: QuickNotifPanel.NotifPanelService",
        "timerService: QuickTimer.TimerService",
        "mprisFocus: QuickIsland.MprisFocus",
        "agentsService: QuickIsland.AgentsService",
        "dynamicIslandService: QuickIsland.DynamicIslandService",
        "mediaPlayingState: MprisPlaybackState.Playing",
    ):
        assert binding in registry
    assert "root.notificationService.unreadCount > 0" in model
    assert "root.timerService.timers.count > 0" in model
    assert "root.timerService.nearestCountdown" in model
    assert "root.mprisFocus.activePlayer !== null" in model
    assert "player.playbackState === root.mediaPlayingState" in model
    assert "const hasAgents = root.agentsService.hasData;" in model
    assert "hasData: hasAgents" in model
    assert "root.agentsService.oldestSession" in model
    assert "providerError" not in model


def test_registry_resting_selection_ignores_page_enablement_and_keeps_priority():
    registry = text(
        ".config/quickshell/modules/island/IslandIntegrationRegistryModel.qml"
    )
    selection = registry.split("function _selectRestingSummary", 1)[1].split(
        "function publish", 1
    )[0]
    publish = registry.split("function publish", 1)[1].split(
        "function applySettings", 1
    )[0]
    assert "root.dynamicIslandService.recordingActive" in selection
    assert "Policy.highestRestingSummary(summaries)" in selection
    assert 'kind: "neutral"' in selection
    assert "root._settings" not in selection
    assert "enabled" not in selection
    assert "Policy.availablePageIds(root._settings, nextIntegrations)" in publish
    assert "root._selectRestingSummary(nextIntegrations)" in publish


def test_registry_watches_exact_settings_path_and_retains_last_valid_state():
    registry = text(
        ".config/quickshell/modules/island/IslandIntegrationRegistry.qml"
    )
    model = text(
        ".config/quickshell/modules/island/IslandIntegrationRegistryModel.qml"
    )
    assert 'Quickshell.env("XDG_CONFIG_HOME")' in registry
    assert 'Quickshell.env("HOME")' in registry
    assert '"/cloud-center/settings/quickshell/island-integrations.json"' in registry
    file_view = registry.split("FileView {", 1)[1]
    assert "watchChanges: true" in file_view
    assert "onFileChanged: root.reloadSettings()" in file_view
    assert "onLoaded: registry.applySettings(text())" in file_view
    assert "onLoadFailed: registry.settingsLoadFailed()" in file_view

    apply_settings = model.split("function applySettings(raw)", 1)[1].split(
        "function settingsLoadFailed", 1
    )[0]
    assert "JSON.parse(raw)" in apply_settings
    assert "Policy.validSettings(parsed)" in apply_settings
    assert "root._settings = Policy.normalizeSettings(parsed, root._settings);" in apply_settings
    assert apply_settings.index("Policy.validSettings(parsed)") < apply_settings.index(
        "root._settings = Policy.normalizeSettings(parsed, root._settings);"
    )
    assert "root._settings =" not in model.split(
        "function settingsLoadFailed", 1
    )[1].split("Connections {", 1)[0]


def test_registry_publishes_fresh_arrays_and_revision_on_observed_changes():
    registry = text(
        ".config/quickshell/modules/island/IslandIntegrationRegistryModel.qml"
    )
    publish = registry.split("function publish", 1)[1].split(
        "function applySettings", 1
    )[0]
    for token in (
        "root.integrations = nextIntegrations.slice();",
        "root.availablePageIds = nextPageIds.slice();",
        "root.availablePages = nextPages.slice();",
        "root.revision++;",
    ):
        assert token in publish
    for target in (
        "root.notificationService",
        "root.timerService",
        "root.timerService.timers",
        "root.mprisFocus",
        "root.mprisFocus.activePlayer",
        "root.agentsService",
        "root.dynamicIslandService",
    ):
        assert f"target: {target}" in registry
    assert registry.count("root.publish();") >= 10


def test_registry_publishes_integrations_in_normalized_settings_order():
    registry = text(
        ".config/quickshell/modules/island/IslandIntegrationRegistryModel.qml"
    )
    publish = registry.split("function publish", 1)[1].split(
        "function applySettings", 1
    )[0]
    assert "root._settings.order" in publish
    assert "nextIntegrations.push(integrationsById[id]);" in publish


def test_carousel_runtime_survives_data_ticks_and_inflight_page_removal():
    runtime = text(".config/quickshell/IslandCarouselRuntimeTest.qml")
    for forbidden in (
        "DynamicIslandService", "TimerService", "AgentsService", "MprisFocus",
        "Wayland",
    ):
        assert forbidden not in runtime
    result = subprocess.run(
        [
            "timeout", "15s", "qs", "--no-color", "-p",
            ".config/quickshell/IslandCarouselRuntimeTest.qml",
        ],
        cwd=ROOT,
        env={
            **os.environ,
            "QT_QPA_PLATFORM": "offscreen",
            "CLOUDYY_LIGHTWEIGHT": "0",
            "CLOUDYY_REDUCED_MOTION": "0",
            "QS_REDUCED_MOTION": "0",
        },
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "TASK4_CAROUSEL_RUNTIME_FAIL" not in output, output
    assert "TASK4_CAROUSEL_RUNTIME_PASS" in output, output


def test_registry_observes_active_media_without_media_page_instantiation():
    registry = text(
        ".config/quickshell/modules/island/IslandIntegrationRegistryModel.qml"
    )
    assert "target: root.mprisFocus.activePlayer" in registry
    for signal in (
        "onTrackTitleChanged", "onTrackArtistChanged", "onPlaybackStateChanged"
    ):
        assert f"function {signal}()" in registry
    assert "function onActivePlayerChanged()" in registry


def test_registry_runtime_publication_contract():
    runtime = text(".config/quickshell/IslandRegistryRuntimeTest.qml")
    for forbidden in ("cloudyy-timer", "cloudyy-agents", "Hyprland", "Mpris.players"):
        assert forbidden not in runtime
    result = subprocess.run(
        [
            "timeout", "15s", "qs", "--no-color", "-p",
            ".config/quickshell/IslandRegistryRuntimeTest.qml",
        ],
        cwd=ROOT,
        env={**os.environ, "QT_QPA_PLATFORM": os.environ.get(
            "QT_QPA_PLATFORM", "offscreen")},
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "TASK3_REGISTRY_RUNTIME_FAIL" not in output, output
    assert "TASK3_REGISTRY_RUNTIME_PASS" in output, output


def test_resting_pill_renders_every_safe_summary_kind():
    pill = text(".config/quickshell/modules/island/IslandRestingPill.qml")
    for kind in (
        "recording", "countdown", "media", "agent", "notification", "neutral"
    ):
        assert f'kind === "{kind}"' in pill
    assert "property var summary:" in pill
    assert 'font.family: "JetBrainsMono Nerd Font"' in pill
    assert pill.count("Text {") == pill.count("renderType: Text.NativeRendering")
    assert pill.count("textFormat: Text.PlainText") == 2
    for unsafe in ("providerError", "settingsError", "raw", "stderr", "stdout"):
        assert unsafe not in pill
