import QtQuick
Rectangle {
    signal startTimer(string label, string mode, int targetSeconds)
    signal cancel()
    implicitWidth: 200; implicitHeight: 40
    color: "transparent"
}
