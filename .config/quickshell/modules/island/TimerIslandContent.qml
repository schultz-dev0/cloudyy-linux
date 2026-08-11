import QtQuick
import QtQuick.Layouts
import "../.."
import "../timer" as QuickTimer

Item {
    id: root

    property var completedTimer: null

    anchors.fill: parent

    RowLayout {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        Text {
            text: "󰔛"
            color: Theme.islandAccent
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
            renderType: Text.NativeRendering
        }

        ColumnLayout {
            spacing: 1

            Text {
                text: root.completedTimer?.label || "Timer complete"
                color: Theme.islandOnSurface
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
                elide: Text.ElideRight
                Layout.maximumWidth: 230
            }

            Text {
                text: root.completedTimer
                    ? "Completed · " + QuickTimer.TimerService.fmtTime(
                        root.completedTimer.elapsedSeconds)
                    : "Completed"
                color: Theme.islandOnSurfaceVariant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                renderType: Text.NativeRendering
            }
        }
    }
}
