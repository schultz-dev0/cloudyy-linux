import QtQuick
import ".."

Item {
    implicitWidth: clockText.implicitWidth
    implicitHeight: clockText.implicitHeight

    property string nowText: Qt.formatDateTime(new Date(), Style.clockFormat)
    Timer {
        interval: Style.clockRefreshMs; repeat: true; running: true; triggeredOnStart: true
        onTriggered: parent.nowText = Qt.formatDateTime(new Date(), Style.clockFormat)
    }

    Text {
        id: clockText
        anchors.centerIn: parent
        text: parent.nowText
        color: Theme.textPrimary
        font.family: Style.fontFamily
        font.pixelSize: Style.clockTextSize
        font.weight: Font.ExtraBold
        style: Text.Outline
        styleColor: Style.textShadowColor
    }
}
