import QtQuick

// Square L-brackets. No full border. Kill this file + its instances to
// drop the frame. MarginRules is independent.
Item {
    id: root
    anchors.fill: parent
    z: 2
    enabled: false

    property bool open: true
    property int duration: 80
    property bool accentTr: true
    property bool showTopRule: false
    property string topRuleLabel: ""

    readonly property int inset: Theme.frameInset
    readonly property int stroke: Theme.frameStroke
    readonly property int armMax: Theme.frameArmLength
    readonly property int ruleInset: inset + armMax + 8

    property real arm: open ? armMax : 0
    Behavior on arm {
        enabled: Perf.animationsEnabled
        NumberAnimation {
            duration: root.duration
            easing.type: Easing.OutCubic
        }
    }

    readonly property int ax: Math.round(arm)
    readonly property color armColor: Theme.text
    readonly property color trColor: accentTr ? Theme.accent : Theme.text

    // TL
    Rectangle { x: Math.round(root.inset); y: Math.round(root.inset); width: root.ax; height: root.stroke; color: root.armColor }
    Rectangle { x: Math.round(root.inset); y: Math.round(root.inset); width: root.stroke; height: root.ax; color: root.armColor }
    // TR
    Rectangle { x: parent.width - Math.round(root.inset) - root.ax; y: Math.round(root.inset); width: root.ax; height: root.stroke; color: root.trColor }
    Rectangle { x: parent.width - Math.round(root.inset) - root.stroke; y: Math.round(root.inset); width: root.stroke; height: root.ax; color: root.trColor }
    // BL
    Rectangle { x: Math.round(root.inset); y: parent.height - Math.round(root.inset) - root.stroke; width: root.ax; height: root.stroke; color: root.armColor }
    Rectangle { x: Math.round(root.inset); y: parent.height - Math.round(root.inset) - root.ax; width: root.stroke; height: root.ax; color: root.armColor }
    // BR
    Rectangle { x: parent.width - Math.round(root.inset) - root.ax; y: parent.height - Math.round(root.inset) - root.stroke; width: root.ax; height: root.stroke; color: root.armColor }
    Rectangle { x: parent.width - Math.round(root.inset) - root.stroke; y: parent.height - Math.round(root.inset) - root.ax; width: root.stroke; height: root.ax; color: root.armColor }

    Rectangle {
        visible: root.showTopRule
        x: root.ruleInset
        y: Math.round(root.inset)
        width: Math.max(0, parent.width - root.ruleInset * 2)
        height: root.stroke
        color: Theme.hairline
    }

    Text {
        visible: root.showTopRule && root.topRuleLabel !== ""
        x: root.ruleInset + 8
        y: Math.round(root.inset) - height / 2
        text: root.topRuleLabel
        color: Theme.text
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 9
        font.letterSpacing: 1.1
        font.capitalization: Font.AllUppercase
        padding: 0
        leftPadding: 6
        rightPadding: 6
        Rectangle {
            anchors.fill: parent
            z: -1
            color: Theme.surface
        }
    }
}
