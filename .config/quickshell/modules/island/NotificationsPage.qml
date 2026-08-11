pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "." as QuickIsland
import "../notifpanel" as QuickNotifPanel

Item {
    id: root

    readonly property var latestNotification: QuickNotifPanel.NotifPanelService.latestNotification
    readonly property int unreadCount: QuickNotifPanel.NotifPanelService.unreadCount
    readonly property var compactActions: {
        if (!latestNotification)
            return [];

        const actions = latestNotification.actions;
        const compactActions = [];
        const actionCount = Math.min(actions.length, 2);
        for (let i = 0; i < actionCount; i++)
            compactActions.push(actions[i]);
        return compactActions;
    }

    signal activateRequested

    QuickIsland.IslandPageFrame {
        anchors.fill: parent

        leftContent: Item {
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 12
                spacing: 6

                Text {
                    width: parent.width
                    text: root.latestNotification
                        ? (root.latestNotification.appName || "Notification")
                        : "Notifications"
                    color: Theme.islandOnSurface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                }

                Text {
                    width: parent.width
                    text: root.latestNotification
                        ? (root.latestNotification.summary || "Notification")
                        : "All clear"
                    color: Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }
            }

            TapHandler {
                onTapped: root.activateRequested()
            }
        }

        rightContent: Item {
            Column {
                anchors.centerIn: parent
                width: parent.width - 20
                spacing: 6

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: String(root.unreadCount)
                    color: Theme.islandOnSurface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    renderType: Text.NativeRendering
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "unread"
                    color: Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    renderType: Text.NativeRendering
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    visible: root.latestNotification !== null

                    Repeater {
                        model: root.compactActions

                        delegate: Rectangle {
                            id: actionButton

                            required property var modelData

                            width: Math.min(112, actionLabel.implicitWidth + 18)
                            height: 24
                            radius: 8
                            color: actionTap.pressed
                                ? Theme.islandPressed
                                : Theme.islandHover
                            visible: modelData.text.length > 0

                            Text {
                                id: actionLabel
                                anchors.centerIn: parent
                                text: actionButton.modelData.text
                                color: Theme.islandOnSurface
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                renderType: Text.NativeRendering
                                elide: Text.ElideRight
                            }

                            TapHandler {
                                id: actionTap
                                onTapped: QuickNotifPanel.NotifPanelService.invokeAction(
                                    root.latestNotification,
                                    actionButton.modelData.identifier)
                            }
                        }
                    }
                }
            }

        }
    }
}
