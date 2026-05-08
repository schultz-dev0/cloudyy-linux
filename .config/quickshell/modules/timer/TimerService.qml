pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool open: false
    readonly property ListModel timers: ListModel {}
    property string homeDir: ""

    readonly property Process _homeReader: Process {
        command: ["sh", "-c", "echo $HOME"]
        running: true
        stdout: SplitParser {
            onRead: line => root.homeDir = line.trim()
        }
    }
}
