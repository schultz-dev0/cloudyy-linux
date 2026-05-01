import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../.."
import "../../overview/services"

PanelWindow {
    id: spotlight

    // ── Tunables ──────────────────────────────────────────────────────────
    readonly property string webSearchUrl:   "https://duckduckgo.com/?q="
    readonly property int    overlayWidth:   640
    readonly property int    topMargin:      80
    readonly property int    maxFileResults: 10
    readonly property int    debounceMs:     120

    // ── State ─────────────────────────────────────────────────────────────
    property bool   spotlightVisible: false
    property string query:            ""
    property var    results:          []
    property int    selectedIndex:    0

    // ── Window ────────────────────────────────────────────────────────────
    anchors { top: true; left: true; right: true }
    implicitHeight: contentPanel.implicitHeight + topMargin
    exclusiveZone:  0
    WlrLayershell.layer:         WlrLayer.Top
    WlrLayershell.namespace:     "quickshell:spotlight"
    WlrLayershell.keyboardFocus: spotlightVisible
                                   ? WlrKeyboardFocus.Exclusive
                                   : WlrKeyboardFocus.OnDemand
    color: "transparent"

    // ── Launch helper ─────────────────────────────────────────────────────
    Component { id: procProto; Process {} }
    function launch(cmd) {
        if (!cmd || cmd.length === 0) return
        const p = procProto.createObject(spotlight, { command: cmd })
        p.runningChanged.connect(() => { if (!p.running) p.destroy() })
        p.running = true
    }

    // ── Search backend ────────────────────────────────────────────────────
    readonly property string searchScript:
        Qt.resolvedUrl("search.sh").toString().replace("file://", "")

    Process {
        id: searchProc
        environment: ({ MAX_FILE_RESULTS: spotlight.maxFileResults.toString() })
        stdout: StdioCollector {
            id: searchOutput
            onStreamFinished: {
                const runningClasses = new Set(
                    HyprlandData.windowList.map(w => (w.class || "").toLowerCase())
                )
                spotlight.results = searchOutput.text
                    .trim().split("\n")
                    .filter(l => l.length > 0)
                    .flatMap(line => {
                        try {
                            const r = JSON.parse(line)
                            if (r.type === "app")
                                r.isRunning = runningClasses.has((r.wmclass || "").toLowerCase())
                            return [r]
                        } catch (_) { return [] }
                    })
                spotlight.selectedIndex = 0
            }
        }
    }

    Timer {
        id: debounceTimer
        interval: spotlight.debounceMs
        repeat:   false
        onTriggered: {
            if (spotlight.query.length === 0) {
                spotlight.results = []
                return
            }
            searchProc.running = false          // kill any in-flight search
            spotlight.results = []
            searchProc.command = ["bash", spotlight.searchScript, spotlight.query]
            searchProc.running = true
        }
    }

    onQueryChanged: debounceTimer.restart()

    // ── Activate result at index ──────────────────────────────────────────
    function activateIndex(idx) {
        if (idx < results.length) {
            const r = results[idx]
            if (r.type === "app") {
                if (r.isRunning)
                    Hyprland.dispatch("focuswindow class:" + r.wmclass)
                else
                    launch(["uwsm-app", "--", r.exec])
            } else {
                launch(["xdg-open", r.path])
            }
        } else {
            launch(["xdg-open", webSearchUrl + encodeURIComponent(query)])
        }
        spotlightVisible = false
    }

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        propagateComposedEvents: true
        onClicked: {
            spotlight.spotlightVisible = false
            mouse.accepted = false
        }
    }

    // ── Content panel ─────────────────────────────────────────────────────
    Item {
        id: contentPanel
        width:         spotlight.overlayWidth
        implicitHeight: searchBar.height + resultCol.implicitHeight
        anchors.horizontalCenter: parent.horizontalCenter
        y: spotlight.spotlightVisible ? spotlight.topMargin : -(implicitHeight + 10)

        Behavior on y {
            NumberAnimation {
                duration: 180
                easing.type: spotlight.spotlightVisible ? Easing.OutCubic : Easing.InCubic
            }
        }

        // Glass pill background
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Qt.rgba(Theme.surface_container.r,
                           Theme.surface_container.g,
                           Theme.surface_container.b, 0.92)
            border.color: Qt.rgba(Theme.outline_variant.r,
                                  Theme.outline_variant.g,
                                  Theme.outline_variant.b, 0.25)
            border.width: 1
        }

        // ── Search bar ────────────────────────────────────────────────────
        Item {
            id: searchBar
            width:  parent.width
            height: 52

            Row {
                anchors {
                    left: parent.left; right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 16; rightMargin: 16
                }
                spacing: 10

                Text {
                    text: "⌕"
                    color: Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.55)
                    font.pixelSize: 20
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    width:  parent.width - 30 - parent.spacing
                    height: 24
                    anchors.verticalCenter: parent.verticalCenter

                    // Placeholder
                    Text {
                        visible: searchInput.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        text:  "Search apps, files, web…"
                        color: Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.4)
                        font.pixelSize: 16
                        font.family:    "JetBrainsMono Nerd Font"
                    }

                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        color:        Theme.textPrimary
                        font.pixelSize: 16
                        font.family:    "JetBrainsMono Nerd Font"
                        selectByMouse:  true
                        text: spotlight.query

                        onTextChanged: spotlight.query = text

                        Keys.onEscapePressed: { spotlight.spotlightVisible = false; event.accepted = true }
                        Keys.onUpPressed: {
                            spotlight.selectedIndex = Math.max(0, spotlight.selectedIndex - 1)
                            event.accepted = true
                        }
                        Keys.onDownPressed: {
                            spotlight.selectedIndex = Math.min(
                                spotlight.results.length,
                                spotlight.selectedIndex + 1
                            )
                            event.accepted = true
                        }
                        Keys.onReturnPressed: {
                            spotlight.activateIndex(spotlight.selectedIndex)
                            event.accepted = true
                        }
                    }
                }
            }

            // Divider shown only when results are present
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height:  1
                visible: spotlight.query.length > 0
                color:   Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g,
                                 Theme.outline_variant.b, 0.18)
            }
        }

        // ── Results ───────────────────────────────────────────────────────
        Column {
            id: resultCol
            width: parent.width
            anchors.top: searchBar.bottom

            Repeater {
                model: spotlight.results
                SpotlightRow {
                    required property var  modelData
                    required property int  index
                    resultData:  modelData
                    isSelected:  index === spotlight.selectedIndex
                    rowWidth:    spotlight.overlayWidth
                    onActivated: spotlight.activateIndex(index)
                    onHovered:   spotlight.selectedIndex = index
                }
            }

            // Web row — always last when query is non-empty
            SpotlightRow {
                visible:    spotlight.query.length > 0
                resultData: ({ type: "web", query: spotlight.query })
                isSelected: spotlight.selectedIndex === spotlight.results.length
                rowWidth:   spotlight.overlayWidth
                onActivated: spotlight.activateIndex(spotlight.results.length)
                onHovered:   spotlight.selectedIndex = spotlight.results.length
            }
        }
    }

    // ── IPC ───────────────────────────────────────────────────────────────
    IpcHandler {
        target: "spotlight"
        function toggle() { spotlight.spotlightVisible = !spotlight.spotlightVisible }
        function show()   { spotlight.spotlightVisible = true }
        function hide()   { spotlight.spotlightVisible = false }
    }

    onSpotlightVisibleChanged: {
        if (spotlightVisible) {
            searchInput.forceActiveFocus()
        } else {
            searchInput.text = ""
            query         = ""
            results       = []
            selectedIndex = 0
        }
    }
}
