pragma ComponentBehavior: Bound

// NotificationPopups.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property var notifServer: null
    property var popups: []
    property int popupSerial: 0

    readonly property int popupWidth: 360
    readonly property int topGap: 56
    readonly property int rightGap: 20
    readonly property int popupSpacing: 10
    readonly property int popupPadding: 14
    readonly property int popupLifetimeMs: 5000
    readonly property int popupFadeMs: 500

    function enqueueNotification(notif) {
        const popupKey = `popup-${popupSerial++}`;
        const timeoutMs = notif.expireTimeout > 0
            ? Math.min(Math.round(notif.expireTimeout * 1000), root.popupLifetimeMs)
            : root.popupLifetimeMs;
        const next = root.popups.slice();
        next.unshift({
            popupKey,
            notificationId: notif.id,
            appName: notif.appName || "",
            summary: notif.summary || "",
            body: notif.body || "",
            urgency: notif.urgency,
            timeoutMs
        });
        root.popups = next;
        return popupKey;
    }

    function removePopup(popupKey) {
        root.popups = root.popups.filter(p => p.popupKey !== popupKey);
    }

    function dismissNotification(popupKey, notificationId) {
        if (root.notifServer) {
            const tracked = root.notifServer.trackedNotifications.values.find(n => n.id === notificationId) ?? null;
            if (tracked)
                tracked.dismiss();
        }

        root.removePopup(popupKey);
    }

    anchors {
        top: true
        right: true
    }
    margins {
        top: topGap
        right: rightGap
    }
    implicitWidth: popupWidth
    implicitHeight: popupColumn.implicitHeight
    exclusiveZone: 0
    color: "transparent"
    visible: root.popups.length > 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:notifications"

    Column {
        id: popupColumn
        width: root.popupWidth
        spacing: root.popupSpacing

        Repeater {
            model: root.popups

            delegate: Rectangle {
                id: toast
                required property var modelData
                property bool fading: false

                width: popupColumn.width
                implicitHeight: contentColumn.implicitHeight + root.popupPadding * 2
                radius: 18
                opacity: fading ? 0 : 1
                color: modelData.urgency === 2
                    ? Qt.rgba(Theme.error_container.r, Theme.error_container.g, Theme.error_container.b, 0.92)
                    : Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.94)
                border.color: modelData.urgency === 2
                    ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.65)
                    : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.38)
                border.width: 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.popupFadeMs
                        easing.type: Easing.OutQuad
                    }
                }

                Column {
                    id: contentColumn
                    anchors {
                        fill: parent
                        margins: root.popupPadding
                    }
                    spacing: 6

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: toast.modelData.appName !== "" ? toast.modelData.appName : "Notification"
                            color: Theme.on_surface_variant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            text: "󰅖"
                            color: Qt.rgba(Theme.on_surface_variant.r, Theme.on_surface_variant.g, Theme.on_surface_variant.b, 0.8)
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.dismissNotification(toast.modelData.popupKey, toast.modelData.notificationId)
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: toast.modelData.summary
                        color: Theme.on_surface
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: toast.modelData.body !== ""
                        width: parent.width
                        text: toast.modelData.body
                        color: Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.82)
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                    }
                }

                Timer {
                    interval: Math.max(0, toast.modelData.timeoutMs - root.popupFadeMs)
                    running: true
                    repeat: false
                    onTriggered: toast.fading = true
                }

                Timer {
                    interval: toast.modelData.timeoutMs
                    running: true
                    repeat: false
                    onTriggered: root.removePopup(toast.modelData.popupKey)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.dismissNotification(toast.modelData.popupKey, toast.modelData.notificationId)
                }
            }
        }
    }
}
