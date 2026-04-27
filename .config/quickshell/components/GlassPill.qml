import QtQuick
import ".."

Rectangle {
    property alias content: container.data
    implicitWidth: container.implicitWidth + (Style.pillPaddingX * 2)
    implicitHeight: Style.barHeight
    radius: Style.barRadius
    antialiasing: true

    // Soft sky gradient base (Aero)
    gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop { position: 0.0; color: Qt.rgba(Theme.skyTop.r, Theme.skyTop.g, Theme.skyTop.b, Style.barGradientTopAlpha) }
        GradientStop { position: 1.0; color: Qt.rgba(Theme.skyBottom.r, Theme.skyBottom.g, Theme.skyBottom.b, Style.barGradientBotAlpha) }
    }
    border.width: 1
    border.color: Theme.glassEdge

    // Glossy top highlight (Aero "wet" sheen)
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.margins: 1
        height: parent.height * Style.barSheenRatio
        radius: parent.radius - 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Style.sheenAlphaTopStrong) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, Style.sheenAlphaBottom) }
        }
    }

    // Soft drop shadow (macOS depth)
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 2
        radius: parent.radius
        color: "transparent"
        border.color: Theme.glassShadow
        border.width: 1
        opacity: 0.4
        z: -1
    }

    Item {
        id: container
        anchors.centerIn: parent
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }
}
