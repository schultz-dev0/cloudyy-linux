pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root
    property bool overviewOpen: false
    // Release layer keyboard before hiding the overlay (Hyprland needs a frame gap).
    property bool overviewKeyboardGrab: false
    property bool superReleaseMightTrigger: true
}
