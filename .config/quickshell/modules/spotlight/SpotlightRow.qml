pragma ComponentBehavior: Bound

// modules/spotlight/SpotlightRow.qml — one-line row (VISUAL-LANGUAGE.md rule 2):
// icon · label · right slot (live state / location only) · › if it drills down.
import QtQuick
import Quickshell
import "../.."
import "../../overview/services"

Item {
    id: root

    required property var  resultData
    required property bool isSelected
    required property int  rowWidth
    property bool isRunning: false

    signal activated()
    signal newInstanceRequested()
    signal hovered()

    readonly property string type: resultData.type ?? ""
    readonly property bool isInline: type === "calculator" || type === "currency" || type === "time"

    readonly property string labelText: {
        if (type === "web")
            return `Search DDG for "${resultData.query}"`;
        if (isInline)
            return resultData.result ?? "";
        return resultData.name ?? resultData.label ?? "";
    }

    // Rule 2: only what you can't otherwise see. Keybind = its keys,
    // currency = rate/date (the conversion's provenance), app = Running.
    readonly property string rightText: {
        if (type === "app")
            return resultData.isRunning ? "Running" : "";
        if (type === "keybind")
            return resultData.combo ?? "";
        if (type === "currency")
            return resultData.subtitle ?? "";
        if (type === "file")   // location: the folder, home as ~ (elides from the left)
            return (resultData.path ?? "").replace(/\/[^/]*$/, "").replace(Quickshell.env("HOME") || "\u0000", "~");
        return resultData.state || resultData.context || "";
    }

    width:  rowWidth
    height: 38

    // Selection highlight
    Rectangle {
        anchors { fill: parent; topMargin: 3; bottomMargin: 3; leftMargin: 10; rightMargin: 10 }
        radius: 2
        color: root.isSelected
            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
            : "transparent"
        Behavior on color { ColorAnimation { duration: 80 } }
    }

    // ── Icon ──────────────────────────────────────────────────────────────
    Item {
        id: iconBox
        width: 28; height: 28
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }

        AppIcon {
            anchors.fill: parent
            visible: root.type === "app"
            iconSize: 28
            iconName: root.resultData.icon ?? "application-x-executable"
            iconPath: root.resultData.iconPath ?? ""
        }

        Text {
            anchors.fill: parent
            visible: root.type !== "app"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment:   Text.AlignVCenter
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 20
            color: Theme.textMuted
            text: {
                if (root.type === "file") return "󰈔";
                if (root.type === "calculator") return "󰃬";
                if (root.type === "currency") return "󰄔";
                if (root.type === "time") return "󰥔";
                if (root.type === "command" || root.type === "keybind")
                    return root.resultData.icon || "󰧭";
                return "󰖟";
            }
        }
    }

    // ── Chevron (drills into a submenu) ──────────────────────────────────
    Text {
        id: chevron
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        width: root.resultData.navigable ? implicitWidth : 0
        visible: root.resultData.navigable === true
        text: "›"
        color: Theme.textMuted
        opacity: 0.6
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 13
    }

    // ── Right slot ────────────────────────────────────────────────────────
    Text {
        id: rightSlot
        anchors {
            right: chevron.left
            rightMargin: chevron.visible ? 8 : 0
            verticalCenter: parent.verticalCenter
        }
        width: Math.min(implicitWidth, root.rowWidth * 0.45)
        visible: text !== ""
        text: root.rightText
        color: root.resultData.isActive ? Theme.accent : Theme.textMuted
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 11
        elide: Text.ElideLeft
    }

    // ── Label ─────────────────────────────────────────────────────────────
    Text {
        anchors {
            left: iconBox.right; leftMargin: 10
            right: rightSlot.visible ? rightSlot.left : chevron.left
            rightMargin: 12
            verticalCenter: parent.verticalCenter
        }
        text: root.labelText
        color: {
            if (root.type === "web")
                return Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.6);
            if (root.resultData.isActive)
                return Theme.accent;
            return Theme.text;
        }
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: root.isInline ? 15 : 13
        font.weight: root.isInline ? Font.Medium : (root.resultData.isActive ? Font.DemiBold : Font.Normal)
        elide: Text.ElideRight
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
