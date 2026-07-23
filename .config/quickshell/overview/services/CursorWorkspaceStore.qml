pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helperPath: decodeURIComponent(
        Qt.resolvedUrl("cursor_workspace.py").toString().replace("file://", ""))
    property var recentUris: []
    property bool loaded: false

    function refresh() {
        workspaceProcess.running = false;
        workspaceProcess.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: workspaceProcess
        command: ["python3", root.helperPath, "list"]
        stdout: StdioCollector {
            id: workspaceOutput
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(workspaceOutput.text);
                    root.recentUris = Array.isArray(parsed?.workspaces)
                        ? parsed.workspaces.filter(uri => typeof uri === "string" && uri.length > 0)
                        : [];
                } catch (error) {
                    console.warn("cursor-workspaces: invalid helper output", error);
                    root.recentUris = [];
                }
                root.loaded = true;
            }
        }
    }
}
