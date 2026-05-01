import QtQuick
import Quickshell

ShellRoot {
    Component.onCompleted: {
        console.log("Current icon theme:", Quickshell.iconTheme)
        Quickshell.iconTheme = "Papirus-Dark"
        console.log("New icon theme:", Quickshell.iconTheme)
        console.log("Path for bssh:", Quickshell.iconPath("network-wired", "fallback"))
        Qt.quit()
    }
}
