from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class AgentsServiceContractTest(unittest.TestCase):
    def test_service_exposes_refresh_data_and_focus_contract(self):
        service = _text(".config/quickshell/modules/island/AgentsService.qml")
        for token in (
            "readonly property var usageRecords:",
            "readonly property var liveSessions:",
            "readonly property var oldestSession:",
            "readonly property bool hasData:",
            "function refreshUsage()",
            "function refreshSessions()",
            "function focusSession(agentId, pid, startedAt)",
        ):
            self.assertIn(token, service)

    def test_service_uses_separate_refresh_cadences_and_generation_guards(self):
        service = _text(".config/quickshell/modules/island/AgentsService.qml")
        self.assertIn("interval: 5000", service)
        self.assertIn("interval: 30000", service)
        self.assertIn("Policy.parseUsageSnapshot(", service)
        self.assertIn("Policy.parseSessionsSnapshot(", service)
        self.assertIn("root._activeUsageGeneration", service)
        self.assertIn("root._usageGeneration", service)
        self.assertIn("root._activeSessionsGeneration", service)
        self.assertIn("root._sessionsGeneration", service)

    def test_focus_passes_complete_approved_identity(self):
        service = _text(".config/quickshell/modules/island/AgentsService.qml")
        focus = service.split("function focusSession(agentId, pid, startedAt)", 1)[1]
        for token in (
            '"--agent-id", agentId',
            '"--pid", String(pid)',
            '"--started-at", startedAt',
        ):
            self.assertIn(token, focus)

    def test_service_never_publishes_provider_output_or_raw_errors(self):
        service = _text(".config/quickshell/modules/island/AgentsService.qml")
        for forbidden in (
            "providerError", "errorOutput", "stderr", "exitCode +", "output.text",
        ):
            self.assertNotIn(forbidden, service)


class AgentsPageContractTest(unittest.TestCase):
    def test_page_and_service_are_registered(self):
        qmldir = _text(".config/quickshell/modules/island/qmldir")
        self.assertIn("AgentsPage 1.0 AgentsPage.qml", qmldir)
        self.assertIn("singleton AgentsService 1.0 AgentsService.qml", qmldir)

    def test_compact_and_expanded_views_use_provider_identity_and_plan(self):
        page = _text(".config/quickshell/modules/island/AgentsPage.qml")
        self.assertIn("root.compactRecord.providerName", page)
        self.assertIn("root.compactRecord.planLabel", page)
        self.assertIn("root.selectedRecord.providerName", page)
        self.assertIn("root.selectedRecord.planLabel", page)
        self.assertIn("Policy.tightestAllowance", page)

    def test_provider_tabs_are_generated_and_allowance_meters_are_three_pixels(self):
        page = _text(".config/quickshell/modules/island/AgentsPage.qml")
        self.assertIn("model: root.providerRecords", page)
        self.assertIn("model: root.selectedRecord ? root.selectedRecord.allowances : []", page)
        self.assertIn("width: parent.width", page)
        self.assertIn("height: 3", page)
        self.assertIn("Theme.islandAccent", page)
        self.assertIn("Theme.error", page)

    def test_provider_view_has_only_one_open_sessions_action_without_live_state(self):
        page = _text(".config/quickshell/modules/island/AgentsPage.qml")
        self.assertEqual(page.count('text: "Open sessions ›"'), 1)
        self.assertNotIn("liveSessions.length", page)
        self.assertNotIn("sessionCount", page)
        self.assertNotIn("statusDot", page)

    def test_sessions_back_and_escape_return_to_providers_first(self):
        page = _text(".config/quickshell/modules/island/AgentsPage.qml")
        self.assertIn('property string pageView: "providers"', page)
        self.assertIn('root.pageView = "sessions";', page)
        self.assertIn('root.pageView = "providers";', page)
        escape = page.split("Keys.onEscapePressed:", 1)[1]
        self.assertIn('if (root.pageView === "sessions")', escape)
        self.assertIn('root.pageView = "providers";', escape)
        self.assertIn("event.accepted = false;", escape)

    def test_entering_agents_from_any_page_restores_provider_first(self):
        page = _text(".config/quickshell/modules/island/AgentsPage.qml")
        lifecycle = page.split("function _enterAgentsPage()", 1)[1].split(
            "function focusInitial()", 1
        )[0]
        self.assertIn('root.pageView = "providers";', lifecycle)

        state_connections = page.split(
            "target: QuickIsland.IslandState", 1
        )[1].split("Timer {", 1)[0]
        self.assertIn("function onCurrentPageChanged()", state_connections)
        current_page_handler = state_connections.split(
            "function onCurrentPageChanged()", 1
        )[1]
        self.assertIn(
            'QuickIsland.IslandState.currentPage === "agents"',
            current_page_handler,
        )
        self.assertIn("root._enterAgentsPage();", current_page_handler)

    def test_active_agents_page_refreshes_elapsed_time_on_entry_and_each_minute(self):
        page = _text(".config/quickshell/modules/island/AgentsPage.qml")
        self.assertIn("readonly property bool pageActive:", page)
        page_active = page.split("readonly property bool pageActive:", 1)[1].split(
            "readonly property bool detailActive:", 1
        )[0]
        self.assertIn('QuickIsland.IslandState.currentPage === "agents"', page_active)
        self.assertIn('QuickIsland.IslandState.mode !== "resting"', page_active)

        lifecycle = page.split("function _enterAgentsPage()", 1)[1].split(
            "function focusInitial()", 1
        )[0]
        self.assertIn("root.presentationTime = Date.now();", lifecycle)
        timer = page.split("Timer {", 1)[1].split("QuickIsland.IslandPageFrame", 1)[0]
        self.assertIn("interval: 60000", timer)
        self.assertIn("running: root.pageActive", timer)
        self.assertIn("onTriggered: root.presentationTime = Date.now()", timer)

    def test_sessions_use_keyboard_scrolling_and_keep_focused_rows_visible(self):
        page = _text(".config/quickshell/modules/island/AgentsPage.qml")
        sessions = page.split('visible: root.pageView === "sessions"', 1)[1]
        for token in (
            "ListView {",
            "id: sessionsList",
            "bottom: parent.bottom",
            "clip: true",
            "boundsBehavior: Flickable.StopAtBounds",
            "activeFocusOnTab: root.detailActive",
            "keyNavigationEnabled: true",
            "required property int index",
            "onActiveFocusChanged:",
            "sessionsList.positionViewAtIndex(index, ListView.Contain)",
        ):
            self.assertIn(token, sessions)
        self.assertIn("width: sessionsList.width", sessions)

    def test_session_activation_passes_agent_pid_and_start_time(self):
        page = _text(".config/quickshell/modules/island/AgentsPage.qml")
        self.assertIn(
            "AgentsService.focusSession(modelData.agentId, modelData.pid, modelData.startedAt)",
            page,
        )

    def test_page_uses_approved_island_visual_language(self):
        page = _text(".config/quickshell/modules/island/AgentsPage.qml")
        for token in (
            "Theme.islandSurface", "Theme.islandBorder", "Theme.islandHover",
            "Theme.islandPressed", 'font.family: "JetBrainsMono Nerd Font"',
            "renderType: Text.NativeRendering",
        ):
            self.assertIn(token, page)


if __name__ == "__main__":
    unittest.main()
