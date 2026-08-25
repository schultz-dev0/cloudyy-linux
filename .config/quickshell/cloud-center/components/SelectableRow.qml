import QtQuick
import ".."

Item {
    id: root

    property bool selected: false
    property bool busy: false
    property bool showDivider: true
    property string title: ""
    property string subtitle: ""
    property string leadingGlyph: ""
    property color leadingColor: Theme.textMuted
    property int dividerInset: 46
    default property alias trailing: trailingSlot.data

    signal clicked()
    signal doubleClicked()
    signal contextMenuRequested(real x, real y)

    implicitHeight: 52
    height: implicitHeight
    width: parent ? parent.width : 0

    Rectangle {
        id: highlight
        anchors.fill: parent
        radius: 2
        color: root.selected
            ? Theme.glass(Theme.accent, 0.20)
            : (rowHover.hovered ? Theme.glass(Theme.accent, 0.08) : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Row {
        anchors {
            fill: parent
            leftMargin: 10
            rightMargin: 10
        }
        spacing: 12

        Text {
            visible: root.leadingGlyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            horizontalAlignment: Text.AlignHCenter
            text: root.leadingGlyph
            color: root.leadingColor
            renderType: Text.NativeRendering
            font {
                family: "JetBrainsMono Nerd Font"
                pixelSize: 14
                hintingPreference: Font.PreferVerticalHinting
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (root.leadingGlyph !== "" ? 34 : 0)
                - trailingSlot.width - 8
            spacing: 2

            Text {
                width: parent.width
                text: root.title
                elide: Text.ElideRight
                color: Theme.text
                renderType: Text.NativeRendering
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 12
                    weight: Font.Medium
                    hintingPreference: Font.PreferVerticalHinting
                }
            }
            Text {
                visible: root.subtitle !== ""
                width: parent.width
                text: root.subtitle
                elide: Text.ElideRight
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 10
                    hintingPreference: Font.PreferVerticalHinting
                }
            }
        }

        Item {
            id: trailingSlot
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: Math.max(22, childrenRect.height)
        }
    }

    Rectangle {
        visible: root.showDivider
        anchors {
            left: parent.left
            leftMargin: root.dividerInset
            right: parent.right
            rightMargin: 10
            bottom: parent.bottom
        }
        height: 1
        color: Theme.hairline
    }

    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        enabled: !root.busy
        onTapped: root.clicked()
        onDoubleTapped: root.doubleClicked()
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: !root.busy
        onTapped: eventPoint => {
            root.contextMenuRequested(eventPoint.position.x, eventPoint.position.y);
        }
    }
}
