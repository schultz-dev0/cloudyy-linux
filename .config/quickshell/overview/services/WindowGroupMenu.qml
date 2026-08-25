pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../"
import "."

// macOS-style window list for a HyprlandData app group.
Item {
    id: root

    property string groupKey: ""
    property var windowsOverride: []
    property bool open: false
    property int maxMenuWidth: 520
    property bool showGroupLabels: false
    property int measuredTextWidth: 0

    signal windowChosen(var windowData)
    signal dismissed()

    readonly property var windows: {
        if (windowsOverride && windowsOverride.length > 0)
            return windowsOverride;
        return groupKey.length ? HyprlandData.windowsForGroupKey(groupKey) : [];
    }

    function rowLabel(win) {
        const groupLabel = HyprlandData.groupDisplayName(HyprlandData.appGroupKey(win));
        const title = HyprlandData.windowLabel(win);
        if (root.showGroupLabels && groupLabel.length)
            return `${groupLabel} — ${title}`;
        return title;
    }

    function updateMeasuredTextWidth() {
        let maxW = 0;
        const list = root.windows;
        if (!list || list.length === 0) {
            root.measuredTextWidth = 0;
            return;
        }
        for (let i = 0; i < list.length; i++) {
            rowMetrics.text = root.rowLabel(list[i]);
            maxW = Math.max(maxW, rowMetrics.width);
        }
        root.measuredTextWidth = Math.ceil(maxW);
    }

    TextMetrics {
        id: rowMetrics
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 12
    }

    readonly property int menuWidth: {
        if (!open || windows.length === 0)
            return 0;
        const inner = Math.max(200, measuredTextWidth);
        return Math.min(root.maxMenuWidth, inner + 52);
    }

    readonly property int menuHeight: {
        if (!open || windows.length === 0)
            return 0;
        return windows.length * 38 + Math.max(0, windows.length - 1) * 2 + 16;
    }

    width: menuWidth
    height: menuHeight

    readonly property bool pointerInside: menuHover.hovered

    function close() {
        dismissed();
    }

    onOpenChanged: {
        if (open)
            updateMeasuredTextWidth();
    }

    onGroupKeyChanged: updateMeasuredTextWidth()
    onWindowsOverrideChanged: updateMeasuredTextWidth()
    Component.onCompleted: updateMeasuredTextWidth()

    HoverHandler {
        id: menuHover
        enabled: root.open
    }

    Rectangle {
        anchors.fill: parent
        visible: root.open && root.windows.length > 0
        radius: 12
        color: Theme.glassShell
        border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.35)
        border.width: 1

        ColumnLayout {
            id: menuCol

            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            Repeater {
                model: root.windows

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredWidth: root.menuWidth - 16
                    Layout.preferredHeight: 36
                    radius: 8
                    color: rowHover.hovered
                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                        : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            text: `${index + 1}`
                            color: Theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            Layout.preferredWidth: 18
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.maximumWidth: root.menuWidth - 52
                            text: root.rowLabel(modelData)
                            color: Theme.text
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    HoverHandler {
                        id: rowHover
                    }

                    MouseArea {
                        id: rowMouse

                        anchors.fill: parent
                        onClicked: root.windowChosen(modelData)
                    }
                }
            }
        }
    }
}
