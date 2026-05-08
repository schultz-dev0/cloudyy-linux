import QtQuick
Rectangle {
    required property string timerId
    required property string label
    required property string mode
    required property int    targetSeconds
    required property int    elapsedSeconds
    required property string timerState
    implicitWidth: 200; implicitHeight: 40
    color: "transparent"
}
