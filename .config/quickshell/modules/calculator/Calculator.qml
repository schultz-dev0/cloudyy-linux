pragma ComponentBehavior: Bound

// modules/calculator/Calculator.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."

import "./backend" as CalcBackend

PanelWindow {
    id: calcWindow

    // ── Calculator Backend ────────────────────────────────────────────────
    CalcBackend.Calculator {
        id: calculator
    }

    // ── Public ────────────────────────────────────────────────────────────
    property bool open: false
    signal requestClose()

    // ── Internal State ────────────────────────────────────────────────────
    readonly property string liveResult:    _liveResult
    readonly property bool   hasResult:     _hasResult
    readonly property bool   resultIsError: _resultIsError

    property string _liveResult:     ""
    property bool   _hasResult:      false
    property bool   _resultIsError:  false
    property bool   _justCopied:     false

    // ── Tunables ──────────────────────────────────────────────────────────
    readonly property int panelWidth:   340
    readonly property int panelRadius:  24
    readonly property int padding:      18
    readonly property int topGap:       16
    readonly property int leftGap:      16

    // ── Window ────────────────────────────────────────────────────────────
    anchors { top: true; left: true }
    margins { top: topGap; left: leftGap }
    implicitWidth:  panelWidth
    implicitHeight: panelRect.height
    color:          "transparent"
    visible:        open

    WlrLayershell.layer:         WlrLayer.Top
    WlrLayershell.namespace:     "quickshell:calculator"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        if (open) {
            inputField.text = ""
            Qt.callLater(() => inputField.forceActiveFocus())
        }
    }

    // ── Clipboard helper ─────────────────────────────────────────────────
    Process {
        id: clipProc
        command: ["wl-copy", calcWindow._liveResult]
    }

    // ── Panel shell ───────────────────────────────────────────────────────
    Rectangle {
        id: panelRect
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: contentCol.implicitHeight + calcWindow.padding * 2
        radius: calcWindow.panelRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.85)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
        border.width: 1

        // Popout from top-left: scale + fade
        opacity: calcWindow.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        scale: calcWindow.open ? 1.0 : 0.88
        transformOrigin: Item.TopLeft
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }

        ColumnLayout {
            id: contentCol
            anchors {
                top: parent.top; left: parent.left; right: parent.right
                margins: calcWindow.padding
            }
            spacing: 12

            // ── Header ────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "󰃬  Calculator"
                    color: Theme.on_surface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }

                // Clear button (shown only when there's input)
                Rectangle {
                    width: 28; height: 28
                    radius: 14
                    visible: inputField.text.length > 0
                    color: Qt.rgba(Theme.error_container.r, Theme.error_container.g, Theme.error_container.b, 0.5)
                    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        color: Theme.on_error_container
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { inputField.text = ""; inputField.forceActiveFocus() }
                    }
                }
            }

            // ── Input area ────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 52
                radius: 14
                color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.7)
                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.2)
                border.width: 1

                TextInput {
                    id: inputField
                    anchors { fill: parent; margins: 14 }
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 20
                    color: Theme.on_surface
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    persistentSelection: true

                    onTextChanged: {
                        const t = text.trim()
                        if (t.length === 0) {
                            calcWindow._liveResult    = ""
                            calcWindow._hasResult     = false
                            calcWindow._resultIsError = false
                            calcWindow._justCopied    = false
                            return
                        }
                        const val = calculator.evaluate(t)
                        if (calculator.hasError) {
                            calcWindow._liveResult    = calculator.lastError
                            calcWindow._hasResult     = true
                            calcWindow._resultIsError = true
                        } else {
                            calcWindow._liveResult    = calculator.formatResult(val)
                            calcWindow._hasResult     = true
                            calcWindow._resultIsError = false
                        }
                        calcWindow._justCopied = false
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            calcWindow.requestClose()
                            event.accepted = true
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                   && calcWindow._hasResult && !calcWindow._resultIsError) {
                            clipProc.running = true
                            calcWindow._justCopied = true
                            event.accepted = true
                        }
                    }
                }
            }

            // ── Result area ───────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 44
                radius: 14
                visible: calcWindow._hasResult
                color: calcWindow._resultIsError
                    ? Qt.rgba(Theme.error_container.r, Theme.error_container.g, Theme.error_container.b, 0.35)
                    : Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.35)
                border.color: calcWindow._resultIsError
                    ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.25)
                    : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                border.width: 1

                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    spacing: 8

                    Text {
                        text: "="
                        color: calcWindow._resultIsError ? Theme.error : Theme.primary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        opacity: 0.6
                    }

                    Text {
                        text: calcWindow._justCopied ? "Copied!" : calcWindow._liveResult
                        color: calcWindow._justCopied
                            ? Theme.tertiary
                            : (calcWindow._resultIsError ? Theme.error : Theme.on_surface)
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                        elide: Text.ElideRight

                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    Text {
                        visible: !calcWindow._resultIsError && !calcWindow._justCopied
                        text: "󰆏"
                        color: Theme.on_surface_variant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        opacity: 0.5
                    }
                }
            }

            // ── Hint bar ──────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Text {
                    text: "↵ copy"
                    color: Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    opacity: 0.55
                }

                Text {
                    text: "⎋ close"
                    color: Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    opacity: 0.55
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

    // ── Public API ────────────────────────────────────────────────────────
    // Visibility is owned by shell.qml via the 'open' binding.
    // Use the requestClose signal to ask the parent to close.
}
