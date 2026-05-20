pragma ComponentBehavior: Bound

import QtQuick
import "../../../"
import "../../services"

Item {
    id: root

    required property var windows
    property int maxVisibleIcons: 5
    property int iconSize: 15

    readonly property var groups: groupedWindows()
    readonly property int overflowCount: Math.max(0, groups.length - maxVisibleIcons)

    implicitHeight: iconSize + 8
    visible: groups.length > 0
    clip: true

    function groupKey(window) {
        return `${window?.class || window?.initialClass || window?.initialTitle || ""}`.toLowerCase().trim();
    }

    function groupedWindows() {
        const byKey = ({});
        for (const window of windows ?? []) {
            const key = groupKey(window);
            if (!key)
                continue;
            if (!byKey[key])
                byKey[key] = { window, count: 0 };
            byKey[key].count += 1;
        }
        return Object.keys(byKey).sort().map(key => byKey[key]);
    }

    Row {
        id: iconRow

        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        spacing: 6

        Repeater {
            model: root.groups.slice(0, root.maxVisibleIcons)

            delegate: Item {
                required property var modelData

                width: root.iconSize + (modelData.count > 1 ? 8 : 0)
                height: root.iconSize + 4

                Image {
                    id: icon

                    property int sourceIndex: 0
                    property var sources: HyprlandData.iconSourcesForWindow(modelData.window)

                    width: root.iconSize
                    height: root.iconSize
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    source: sources.length > sourceIndex ? sources[sourceIndex] : ""
                    sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                    fillMode: Image.PreserveAspectFit
                    smooth: true

                    onSourcesChanged: sourceIndex = 0
                    onStatusChanged: {
                        if (status === Image.Error && sourceIndex < sources.length - 1)
                            Qt.callLater(() => {
                                sourceIndex += 1;
                            });
                    }
                }

                Rectangle {
                    visible: modelData.count > 1
                    width: 14
                    height: 14
                    radius: 7
                    anchors.right: parent.right
                    anchors.top: parent.top
                    color: Theme.primary_container
                    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.45)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: modelData.count
                        color: Theme.on_primary_container
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                }
            }
        }

        Text {
            visible: root.overflowCount > 0
            text: "+" + root.overflowCount
            color: Theme.on_surface_variant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            font.weight: Font.Bold
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
