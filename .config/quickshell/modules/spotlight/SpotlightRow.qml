pragma ComponentBehavior: Bound

// modules/spotlight/SpotlightRow.qml
import QtQuick
import Quickshell
import "../.."
import "../../overview/services"

Item {
    id: root

    required property var  resultData   // {type,name,...} or {type:"web",query} or {type:"calculator"|"currency"|"time",expression,result,subtitle?}
    required property bool isSelected
    required property int  rowWidth
    property bool isRunning: false

    signal activated()
    signal newInstanceRequested()
    signal hovered()

    width:  rowWidth
    height: 46

    // Selection highlight
    Rectangle {
        anchors {
            fill: parent
            topMargin: 3
            bottomMargin: 3
            leftMargin: 10
            rightMargin: 10
        }
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

            AppIcon {
                id: iconImg
                anchors.fill: parent
                visible: root.resultData.type === "app"
                iconSize: 28
                iconName: root.resultData.icon ?? "application-x-executable"
                iconPath: root.resultData.iconPath ?? ""
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
                    if (root.resultData.type === "currency") return "󰄔";
                    if (root.resultData.type === "time") return "󰥔";
                    if (root.resultData.type === "command" || root.resultData.type === "keybind")
                        return root.resultData.icon || "󰧭";
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
                    if (root.resultData.type === "calculator" || root.resultData.type === "currency" || root.resultData.type === "time")
                        return root.resultData.result;
                    if (root.resultData.type === "command" || root.resultData.type === "keybind")
                        return root.resultData.name ?? root.resultData.label ?? "";
                    return root.resultData.name ?? "";
                }
                color: {
                    if (root.resultData.type === "calculator" || root.resultData.type === "currency" || root.resultData.type === "time")
                        return Theme.on_surface;
                    if (root.resultData.type === "command" || root.resultData.type === "keybind") {
                        if (root.resultData.isActive)
                            return Theme.primary;
                        return Theme.textPrimary;
                    }
                    if (root.resultData.type === "web")
                        return Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.6);
                    return Theme.textPrimary;
                }
                font.pixelSize: (root.resultData.type === "calculator" || root.resultData.type === "currency" || root.resultData.type === "time") ? 15 : 13
                font.weight: (root.resultData.type === "calculator" || root.resultData.type === "currency" || root.resultData.type === "time")
                    ? Font.Medium
                    : (root.resultData.isActive ? Font.DemiBold : Font.Normal)
                font.family:    "JetBrainsMono Nerd Font"
                elide: Text.ElideRight
            }

            Text {
                width:   parent.width
                visible: root.resultData.type === "app" || root.resultData.type === "file"
                         || root.resultData.type === "calculator" || root.resultData.type === "currency" || root.resultData.type === "time"
                         || root.resultData.type === "command" || root.resultData.type === "keybind"
                text:    {
                    if (root.resultData.type === "app")
                        return root.resultData.isRunning ? "Running" : (root.resultData.exec ?? "");
                    if (root.resultData.type === "calculator")
                        return root.resultData.expression ?? "";
                    if (root.resultData.type === "time")
                        return root.resultData.expression ?? "";
                    if (root.resultData.type === "currency")
                        return root.resultData.subtitle ?? root.resultData.expression ?? "";
                    if (root.resultData.type === "command" || root.resultData.type === "keybind")
                        return root.resultData.subtitle ?? "";
                    return root.resultData.path ?? "";
                }
                color: root.resultData.type === "keybind" ? Theme.on_surface_variant : Theme.textMuted
                font.pixelSize: root.resultData.type === "keybind" ? 12 : 11
                font.family:    "JetBrainsMono Nerd Font"
                elide: Text.ElideMiddle
            }
        }
    }

    // ── Interaction ───────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onEntered: root.hovered()
        onClicked: mouse => {
            if (root.isRunning && mouse) {
                if (mouse.button === Qt.MiddleButton
                        || ((mouse.modifiers ?? 0) & Qt.ShiftModifier) !== 0) {
                    root.newInstanceRequested();
                    return;
                }
            }
            root.activated();
        }
    }
}
