import QtQuick
import ".."

Rectangle {
    id: toast
    property string message: ""
    function show(text) { message = text; opacity = 1; hideTimer.restart(); }

    anchors { bottom: parent.bottom; bottomMargin: 24; horizontalCenter: parent.horizontalCenter }
    width: label.implicitWidth + 32; height: 34; radius: 2
    color: Theme.inverse_surface
    opacity: 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    Text { id: label; anchors.centerIn: parent; text: toast.message
           color: Theme.inverse_on_surface
           font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 } }
    Timer { id: hideTimer; interval: 2500; onTriggered: toast.opacity = 0 }
}
