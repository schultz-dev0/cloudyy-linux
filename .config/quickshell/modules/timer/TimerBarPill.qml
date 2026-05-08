pragma ComponentBehavior: Bound

import QtQuick
import "../.."

Rectangle {
    id: pill

    readonly property var   pt:      TimerService.primaryTimer
    readonly property bool  warning: TimerService.hasCountdownWarning
    readonly property int   count:   TimerService.runningCount

    implicitWidth:  contentRow.implicitWidth + 16
    implicitHeight: 28
    radius:         14
    color:          Qt.rgba(Theme.surface_container.r,
                            Theme.surface_container.g,
                            Theme.surface_container.b, 0.8)

    Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 5

        // Play/idle icon
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  pill.pt ? "▶" : "⏱"
            color: {
                if (!pill.pt)      return Theme.on_surface_variant
                if (pill.warning)  return Theme.error
                return Theme.primary
            }
            font.pixelSize: 11
            font.family:    "JetBrainsMono Nerd Font"
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        // Live time display
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!pill.pt
            text: {
                if (!pill.pt) return ""
                if (pill.pt.mode === "countdown") {
                    const rem = Math.max(0, pill.pt.targetSeconds - pill.pt.elapsedSeconds)
                    return fmtTime(rem)
                }
                return fmtTime(pill.pt.elapsedSeconds)
            }
            color: pill.warning ? Theme.error : Theme.on_surface
            font.pixelSize: 12
            font.family:    "JetBrainsMono Nerd Font"
            font.weight:    Font.Bold
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        // "+N" badge for multiple running timers
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: pill.count > 1
            width:  badgeText.implicitWidth + 8
            height: 16
            radius: 8
            color:  pill.warning
                    ? Qt.rgba(Theme.error_container.r, Theme.error_container.g, Theme.error_container.b, 0.8)
                    : Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.8)

            Text {
                id: badgeText
                anchors.centerIn: parent
                text:       "+" + (pill.count - 1)
                color:      pill.warning ? Theme.on_error_container : Theme.on_primary_container
                font.pixelSize: 9
                font.weight:    Font.Bold
                font.family:    "JetBrainsMono Nerd Font"
            }
        }

        // "Timer" label shown only when idle
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !pill.pt
            text:  "Timer"
            color: Theme.on_surface_variant
            font.pixelSize: 12
            font.family:    "JetBrainsMono Nerd Font"
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape:  Qt.PointingHandCursor
        onClicked:    TimerService.open = !TimerService.open
    }

    function fmtTime(secs) {
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        const s = secs % 60
        if (h > 0)
            return h + ":" + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }
}
