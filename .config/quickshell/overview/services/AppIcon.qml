pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Item {
    id: root

    property var appData: null
    property string iconName: ""
    property string iconPath: ""
    property int iconSize: 48
    property real iconOpacity: 1
    property int fillMode: Image.PreserveAspectFit

    readonly property int implicitWidth: iconSize
    readonly property int implicitHeight: iconSize

    property var sources: []

    function refreshSources() {
        if (appData) {
            sources = IconResolver.sourcesForApp(appData);
            queueUnresolvedLookups(appData);
            return;
        }

        const data = {
            icon: iconName,
            iconPath: iconPath
        };
        if (iconName || iconPath) {
            sources = IconResolver.sourcesForApp(data);
            queueUnresolvedLookups(data);
        } else {
            sources = IconResolver.sourcesForName("application-default-icon");
        }
    }

    function queueUnresolvedLookups(data) {
        // Only a concrete file counts as resolved. Quickshell.iconPath() hands
        // back an "image://icon/<name>" URL even when the Qt icon theme (often
        // Adwaita) has no such icon — trusting that phantom skips the Python
        // fallback that would find it in Fluent-green/Papirus/etc.
        const hasReal = sources.some(s => {
            const value = `${s ?? ""}`;
            return (value.startsWith("file://") || value.startsWith("/"))
                && !value.includes("application-default-icon");
        });
        if (hasReal)
            return;

        const names = [data.icon, data.id, data.wmclass];
        for (let i = 0; i < names.length; i++) {
            const name = `${names[i] ?? ""}`.trim();
            if (name.length > 0)
                IconResolver.lookupNameAsync(name);
        }
    }

    Component.onCompleted: refreshSources()
    onAppDataChanged: refreshSources()
    onIconNameChanged: refreshSources()
    onIconPathChanged: refreshSources()

    Connections {
        target: IconResolver
        function onPathByNameChanged() {
            root.refreshSources();
        }
        function onRuntimeCacheChanged() {
            root.refreshSources();
        }
    }

    Image {
        id: iconImg

        anchors.fill: parent
        property int sourceIndex: 0
        // Load at 2x so magnified dock icons and HiDPI screens stay sharp.
        sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
        smooth: true
        mipmap: true
        antialiasing: true
        fillMode: root.fillMode
        opacity: root.iconOpacity
        source: root.sources[sourceIndex] ?? IconResolver.genericIconSource
        onStatusChanged: {
            if (status === Image.Error && sourceIndex < root.sources.length - 1)
                Qt.callLater(() => {
                    sourceIndex++;
                });
        }
    }

    Connections {
        target: root
        function onSourcesChanged() {
            iconImg.sourceIndex = 0;
        }
    }
}
