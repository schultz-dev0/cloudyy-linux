pragma Singleton
import QtQuick
import Qt.labs.settings
import Quickshell

Singleton {
    id: nav

    property var model: null
    property string currentPageId: ""
    property string searchQuery: ""

    // Quickshell hot-reload still tears down singletons; persist nav page across reloads.
    Settings {
        id: persisted
        category: "nav"
        property string lastPage: ""
        // qs's own OS process id as of the last time this ran. It survives a
        // QML-engine-only reload (same process, source files changed)
        // but differs on a genuinely new launch — the only reliable way to
        // tell those apart, since a reload tears down *everything* QML-side,
        // including this Settings object itself; only what actually hit disk
        // survives. Used below to decide whether lastPage is trustworthy.
        property int lastPid: -1
    }

    function pageById(id) {
        if (!model) return null;
        for (const page of model.pages)
            if (page.id === id) return page;
        return null;
    }

    function navigate(id) {
        // Order matters: pageLoader's sourceComponent ternary reads both
        // searchQuery and currentPageId. Clearing searchQuery first would
        // transiently fall back to the *old* currentPageId (briefly
        // remounting the page you're leaving) before this function updates
        // it. Set currentPageId first so the ternary lands on the target
        // page in one step.
        currentPageId = id;
        searchQuery = "";
        persisted.lastPage = id;
    }

    Connections {
        target: Backend
        function onModelLoaded(m) {
            nav.model = m;
            if (nav.currentPageId === "") {
                const sameProcess = persisted.lastPid === Quickshell.processId;
                if (sameProcess && persisted.lastPage && nav.pageById(persisted.lastPage)) {
                    // Reload of an already-open session — resume where you were.
                    nav.currentPageId = persisted.lastPage;
                } else {
                    // Fresh process. The launcher passes its resolved target
                    // (default "home") via env var at spawn time rather than a
                    // follow-up `qs ipc` call after the window's already up —
                    // that used to race the QML engine's first paint and
                    // visibly flash the old persisted page before jumping.
                    const envTarget = Quickshell.env("CLOUD_CENTER_TARGET_PAGE") ?? "";
                    nav.currentPageId = (envTarget && nav.pageById(envTarget))
                        ? envTarget
                        : m.categories[0].pages[0];
                }
                persisted.lastPid = Quickshell.processId;
            }
        }
    }
}
