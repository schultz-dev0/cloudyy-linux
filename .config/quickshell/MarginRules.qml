import QtQuick

// Layer A — extra labels on the CornerFrame rules.
// Drop this file + its instance to remove the layer. CONTROL stays on CornerFrame.
Item {
    id: root
    anchors.fill: parent
    z: 3
    enabled: false

    readonly property int inset: Theme.frameInset
    readonly property int stroke: Theme.frameStroke
    readonly property int ruleInset: inset + Theme.frameArmLength + 8

    property string topRight: ""
    property string bottomLeft: ""
    property string bottomRight: ""

    Rectangle {
        x: root.ruleInset
        y: parent.height - Math.round(root.inset) - root.stroke
        width: Math.max(0, parent.width - root.ruleInset * 2)
        height: root.stroke
        color: Theme.hairline
    }

    component RuleLabel: Text {
        color: Theme.textMuted
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 9
        font.letterSpacing: 1.1
        font.capitalization: Font.AllUppercase
        leftPadding: 6
        rightPadding: 6
        Rectangle {
            anchors.fill: parent
            z: -1
            color: Theme.surface
        }
    }

    RuleLabel {
        visible: root.topRight !== ""
        x: parent.width - root.ruleInset - 8 - width
        y: Math.round(root.inset) - height / 2
        text: root.topRight
    }

    RuleLabel {
        visible: root.bottomLeft !== ""
        x: root.ruleInset + 8
        y: parent.height - Math.round(root.inset) - height / 2
        text: root.bottomLeft
    }

    RuleLabel {
        visible: root.bottomRight !== ""
        x: parent.width - root.ruleInset - 8 - width
        y: parent.height - Math.round(root.inset) - height / 2
        text: root.bottomRight
    }
}
