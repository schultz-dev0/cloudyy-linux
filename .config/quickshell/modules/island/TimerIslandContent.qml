import QtQuick
import QtQuick.Layouts
import "../.."
import "../timer" as QuickTimer

Item {
    id: root
    readonly property var pt: QuickTimer.TimerService.primaryTimer
    readonly property bool warning: QuickTimer.TimerService.hasCountdownWarning
    readonly property int count: QuickTimer.TimerService.runningCount

    anchors.fill: parent

    RowLayout {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Text {
            text: root.pt ? "▶" : "⏱"
            color: root.warning ? "#ff6b6b" : "#ffffff"
            font.pixelSize: 11
            font.family: "JetBrainsMono Nerd Font"
        }

        Text {
            visible: !!root.pt
            text: {
                if (!root.pt) return ""
                if (root.pt.mode === "countdown")
                    return QuickTimer.TimerService.fmtTime(Math.max(0, root.pt.targetSeconds - root.pt.elapsedSeconds))
                return QuickTimer.TimerService.fmtTime(root.pt.elapsedSeconds)
            }
            color: root.warning ? "#ff6b6b" : "#ffffff"
            font.pixelSize: 12
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Bold
        }

        Text {
            visible: root.count > 1
            text: "+" + (root.count - 1)
            color: Qt.rgba(1, 1, 1, 0.6)
            font.pixelSize: 9
            font.family: "JetBrainsMono Nerd Font"
        }
    }
}
