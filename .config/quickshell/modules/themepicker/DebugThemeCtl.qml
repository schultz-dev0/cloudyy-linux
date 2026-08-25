import QtQuick
import Quickshell

ShellRoot {
    Component.onCompleted: {
        console.log("DEBUG resolvedUrl=" + Qt.resolvedUrl("../../../../bin/cloudyy-theme"));
    }
}
