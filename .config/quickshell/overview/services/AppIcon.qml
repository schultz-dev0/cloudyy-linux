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
        const generic = IconResolver.genericIconSource;
        const hasReal = sources.some(s => {
            const value = `${s ?? ""}`;
            return value.length > 0
                && value !== generic
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
        sourceSize: Qt.size(root.iconSize, root.iconSize)
        smooth: true
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
