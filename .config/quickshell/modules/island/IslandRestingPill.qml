pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root

    property var summary: ({ kind: "neutral" })
    property double presentationTime: Date.now()

    function _formatDuration(seconds) {
        const value = Math.max(0, Math.floor(seconds || 0));
        const hours = Math.floor(value / 3600);
        const minutes = Math.floor((value % 3600) / 60);
        const secs = value % 60;
        if (hours > 0)
            return hours + ":" + String(minutes).padStart(2, "0")
                + ":" + String(secs).padStart(2, "0");
        return String(minutes).padStart(2, "0") + ":" + String(secs).padStart(2, "0");
    }

    function _elapsedSeconds(startedAt) {
        const start = typeof startedAt === "number" ? startedAt : Date.parse(startedAt);
        return Number.isFinite(start) ? (root.presentationTime - start) / 1000 : 0;
    }

    function _icon() {
        const kind = root.summary?.kind ?? "neutral";
        if (kind === "recording") return "\uF03D";
        if (kind === "countdown") return "\uF051B";
        if (kind === "media") return "\uF040A";
        if (kind === "agent") return "\uF0843";
        if (kind === "notification") return "\uF009A";
        if (kind === "neutral") return "\uF0AC";
        return "\uF0AC";
    }

    function _primaryText() {
        const kind = root.summary?.kind ?? "neutral";
        if (kind === "recording") return "Recording";
        if (kind === "countdown") return root.summary.label || "Countdown";
        if (kind === "media") return root.summary.title || "Media";
        if (kind === "agent") return root.summary.agentName || "Agent";
        if (kind === "notification") return root.summary.unreadCount + " unread";
        return "Cloudyy";
    }

    function _secondaryText() {
        const kind = root.summary?.kind ?? "neutral";
        if (kind === "recording")
            return root._formatDuration(root._elapsedSeconds(root.summary.startedAt));
        if (kind === "countdown")
            return root._formatDuration(root.summary.remainingSeconds);
        if (kind === "media") return root.summary.artist || "";
        if (kind === "agent") return root.summary.projectName || "Running";
        if (kind === "notification") return root.summary.summary || "Notifications";
        return "Ready";
    }

    anchors {
        left: parent.left
        right: parent.right
        leftMargin: 12
        rightMargin: 12
    }
    height: parent.height

    Timer {
        interval: 1000
        running: root.summary?.kind === "recording"
        repeat: true
        onTriggered: root.presentationTime = Date.now()
    }

    RowLayout {
        anchors.centerIn: parent
        width: parent.width
        spacing: 6

        Text {
            text: root._icon()
            color: root.summary?.kind === "recording"
                ? Theme.error : Theme.islandOnSurface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: root._primaryText()
            textFormat: Text.PlainText
            color: Theme.islandOnSurface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: root._secondaryText()
            textFormat: Text.PlainText
            color: Theme.islandOnSurfaceVariant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            Layout.maximumWidth: parent.width * 0.42
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
