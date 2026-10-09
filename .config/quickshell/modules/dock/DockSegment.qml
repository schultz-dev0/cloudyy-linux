// modules/dock/DockSegment.qml
// One slot in the dock rail: an app or an open-folder shortcut. Plain inputs
// only; Dock.qml does every lookup. A horizontal segment on top/bottom edges,
// a one-line row on side edges. Sizes come from DockLayout.js.
import QtQuick
import "../.."
import "../../overview/services"
import "DockLayout.js" as DockLayout

Item {
    id: root

    property var appData: null          // app entry; AppIcon resolves its icon
    property string imageSource: ""     // folder icon, used when appData is null
    property string name: ""
    property int ledCount: 0
    property bool focused: false        // the focused app: bold, LEDs filled
    property bool closed: false         // pinned but not running: muted
    property bool selected: false       // keyboard selection: inverted accent block
    property bool vertical: false
    property bool groupStart: false     // stronger divider before the folder group
    property bool isFirst: false        // the first slot draws no leading divider
    property int maxChars: 0            // 0 = full name
    property real charW: 7.2
    property real thickness: 30         // rail inner size across the edge

    signal clicked()
    signal rightClicked()
    signal moveStarted()
    signal moveDragged(var area, var mouse)
    signal moveEnded()
    signal moveCanceled()

    readonly property string shown: DockLayout.shortName(root.name, root.maxChars)
    readonly property int iconPx: root.vertical ? DockLayout.ICON_V : DockLayout.ICON_H
    readonly property int pad: root.vertical ? DockLayout.PAD_V : DockLayout.PAD_H
    readonly property int gap: root.vertical ? DockLayout.GAP_V : DockLayout.GAP_H
    readonly property color fg: root.selected ? Theme.accentText : root.closed ? Theme.textMuted : Theme.text
    readonly property color ledColor: root.selected ? Theme.accentText : Theme.accent

    width: root.vertical ? root.thickness : DockLayout.segmentWidth(root.shown, root.ledCount, root.charW)
    height: root.vertical ? DockLayout.ROW_V : root.thickness

    // Background: inverted accent block when selected, soft fill on hover.
    Rectangle {
        anchors.fill: parent
        color: root.selected ? Theme.accent
            : hover.hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.09)
            : "transparent"
    }

    // Leading divider (top edge of a row on side edges).
    Rectangle {
        visible: !root.isFirst
        width: root.vertical ? parent.width : 1
        height: root.vertical ? 1 : parent.height
        color: root.groupStart ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.55) : Theme.hairline
    }

    Item {
        id: icon
        x: root.pad
        anchors.verticalCenter: parent.verticalCenter
        width: root.iconPx
        height: root.iconPx
        opacity: root.closed && !root.selected ? 0.55 : 1

        AppIcon {
            visible: root.appData !== null
            anchors.fill: parent
            iconSize: root.iconPx
            appData: root.appData
        }

        Image {
            visible: root.appData === null
            anchors.fill: parent
            source: root.imageSource
            sourceSize: Qt.size(root.iconPx * 2, root.iconPx * 2)
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
    }

    Text {
        id: label
        x: root.pad + root.iconPx + root.gap
        anchors.verticalCenter: parent.verticalCenter
        text: root.shown
        color: root.fg
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 12
        font.weight: root.focused || root.selected ? Font.Bold : Font.Normal
    }

    // One LED per window; filled when this is the focused app.
    Row {
        id: leds
        visible: root.ledCount > 0
        spacing: DockLayout.LED_GAP
        anchors.verticalCenter: parent.verticalCenter
        x: root.vertical ? root.width - root.pad - width : label.x + label.implicitWidth + root.gap

        Repeater {
            model: root.ledCount

            Rectangle {
                width: DockLayout.LED
                height: DockLayout.LED
                color: root.focused ? root.ledColor : "transparent"
                border.width: 1
                border.color: root.ledColor
            }
        }
    }

    HoverHandler {
        id: hover
    }

    // Click focuses/launches, right-click pins, a long press starts moving the
    // dock to another edge (the held press keeps delivering motion).
    MouseArea {
        id: area
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        pressAndHoldInterval: 400
        onClicked: mouse => mouse.button === Qt.RightButton ? root.rightClicked() : root.clicked()
        onPressAndHold: mouse => {
            if (mouse.button === Qt.LeftButton)
                root.moveStarted();
        }
        onPositionChanged: mouse => root.moveDragged(area, mouse)
        onReleased: root.moveEnded()
        onCanceled: root.moveCanceled()
    }
}
