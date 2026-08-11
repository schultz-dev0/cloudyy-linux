pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "../timer" as QuickTimer
import "." as QuickIsland

Item {
    id: root

    readonly property var timer: QuickTimer.TimerService.primaryTimer
    readonly property int count: QuickTimer.TimerService.runningCount
    readonly property bool active: count > 0 && QuickIsland.IslandState.mode === "resting"

    anchors {
        left: parent.left
        right: parent.right
        leftMargin: 12
        rightMargin: 12
    }
    height: parent.height
    visible: active

    Row {
        anchors.centerIn: parent
        spacing: 5

        Text {
            text: "󰔛"
            color: Theme.islandOnSurface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: root.count > 1 ? String(root.count) + " \u00B7" : ""
            color: Theme.islandOnSurfaceVariant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            renderType: Text.NativeRendering
            visible: root.count > 1
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: root.timer ? (root.timer.label || "") : ""
            color: Theme.islandOnSurface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            visible: text.length > 0
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: {
                if (!root.timer) return ""
                if (root.timer.mode === "countdown") {
                    const remaining = Math.max(0, root.timer.targetSeconds - root.timer.elapsedSeconds)
                    return QuickTimer.TimerService.fmtTime(remaining)
                }
                return QuickTimer.TimerService.fmtTime(root.timer.elapsedSeconds)
            }
            color: Theme.islandOnSurface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
