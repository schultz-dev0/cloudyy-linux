pragma ComponentBehavior: Bound

// modules/spotlight/SpotlightRow.qml
import QtQuick
import Quickshell
import "../.."

Item {
    id: root

    required property var  resultData   // {type,name,icon?,exec?,wmclass?,isRunning?,path?} or {type:"web",query} or {type:"calculator",expression,result}
    required property bool isSelected
    required property int  rowWidth

    signal activated()
    signal hovered()

    width:  rowWidth
    height: 46

    // Selection highlight
    Rectangle {
        anchors { fill: parent; margins: 3 }
        radius: 8
        color: root.isSelected
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
            : "transparent"
        Behavior on color { ColorAnimation { duration: 80 } }
    }

    Row {
        anchors {
            left: parent.left; right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 14; rightMargin: 14
        }
        spacing: 10

        // ── Icon ──────────────────────────────────────────────────────────
        Item {
            width: 28; height: 28
            anchors.verticalCenter: parent.verticalCenter

            Image {
                id: iconImg
                anchors.fill: parent
                property int fallbackStage: 0
                property string resolvedIconPath: root.resultData.iconPath ?? ""
                property string baseIcon: root.resultData.icon ?? "application-x-executable"
                onResolvedIconPathChanged: fallbackStage = 0
                onBaseIconChanged: fallbackStage = 0
                sourceSize: Qt.size(56, 56)
                smooth:     true
                visible: root.resultData.type === "app"
                source: {
                    if (root.resultData.type !== "app")
                        return "";
                    if (fallbackStage === 0 && resolvedIconPath.length > 0)
                        return resolvedIconPath.startsWith("file://") ? resolvedIconPath : `file://${resolvedIconPath}`;
                    if (fallbackStage <= 1)
                        return Quickshell.iconPath(baseIcon, "image://icon/application-x-executable");
                    return "image://icon/application-x-executable";
                }
                onStatusChanged: {
                    if (status === Image.Error && fallbackStage < 2)
                        fallbackStage++;
                }
            }

            Text {
                anchors.fill: parent
                visible: root.resultData.type !== "app"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment:   Text.AlignVCenter
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 20
                color: Theme.on_surface_variant
                text: {
                    if (root.resultData.type === "file") return "󰈔";
                    if (root.resultData.type === "calculator") return "󰃬";
                    return "󰖟";
                }
            }
        }

        // ── Text ──────────────────────────────────────────────────────────
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            width: root.rowWidth - 28 - 10 - 14 - 14

            Text {
                width: parent.width
                text:  {
                    if (root.resultData.type === "web")
                        return `Search DDG for "${root.resultData.query}"`;
                    if (root.resultData.type === "calculator")
                        return root.resultData.result;
                    return root.resultData.name ?? "";
                }
                color: root.resultData.type === "calculator"
                    ? Theme.on_surface
                    : (root.resultData.type === "web"
                        ? Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.6)
                        : Theme.textPrimary)
                font.pixelSize: root.resultData.type === "calculator" ? 15 : 13
                font.weight:    root.resultData.type === "calculator" ? Font.Medium : Font.Normal
                font.family:    "JetBrainsMono Nerd Font"
                elide: Text.ElideRight
            }

            Text {
                width:   parent.width
                visible: root.resultData.type === "app" || root.resultData.type === "file"
                         || root.resultData.type === "calculator"
                text:    {
                    if (root.resultData.type === "app")
                        return root.resultData.isRunning ? "Running" : (root.resultData.exec ?? "");
                    if (root.resultData.type === "calculator")
                        return root.resultData.expression ?? "";
                    return root.resultData.path ?? "";
                }
                color:   Theme.textMuted
                font.pixelSize: 11
                font.family:    "JetBrainsMono Nerd Font"
                elide: Text.ElideMiddle
            }
        }
    }

    // ── Interaction ───────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hovered()
        onClicked: root.activated()
    }
}
