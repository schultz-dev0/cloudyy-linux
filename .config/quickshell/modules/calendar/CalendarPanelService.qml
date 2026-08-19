pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: svc

    property bool visible: false

    function open() {
        svc.visible = true;
    }

    function close() {
        svc.visible = false;
    }

    function toggle() {
        svc.visible = !svc.visible;
    }
}
