import QtQuick

Rectangle {
    id: root
    property string cardTitle: ""
    property string cardSubtitle: ""
    property string buttonLabel: ""
    signal clicked()

    height: 64
    radius: 10
    color: Theme.surface_container

    Column {
        anchors { left: parent.left; leftMargin: 18; right: button.left; rightMargin: 12
                  verticalCenter: parent.verticalCenter }
        spacing: 2
        Text {
            text: root.cardTitle
            color: Theme.on_surface
            width: parent.width
            elide: Text.ElideRight
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 15; weight: Font.DemiBold }
            renderType: Text.NativeRendering
        }
        Text {
            text: root.cardSubtitle
            color: Theme.on_surface_variant
            width: parent.width
            wrapMode: Text.WordWrap
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
            renderType: Text.NativeRendering
        }
    }

    Rectangle {
        id: button
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        width: buttonText.implicitWidth + 24
        height: 32
        radius: 8
        color: buttonArea.containsMouse ? Theme.primary : Theme.primary_container

        Text {
            id: buttonText
            anchors.centerIn: parent
            text: root.buttonLabel
            color: buttonArea.containsMouse ? Theme.on_primary : Theme.on_primary_container
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium }
            renderType: Text.NativeRendering
        }

        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }
}
