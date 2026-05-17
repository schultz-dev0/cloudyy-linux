import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../common"
import "../../common/functions"
import "../../common/widgets"
import "../../services"
import "."

Item {
    id: root
    required property var panelWindow
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)

    property var windowByAddress: HyprlandData.windowByAddress
    property var monitorData: HyprlandData.monitors.find(m => m.id === root.monitor?.id)
    property real scale: Config.options.overview.scale || 0.16
    property color activeBorderColor: Appearance.colors.colSecondary
    property real workspaceSpacing: Config.options.overview.workspaceSpacing
    property bool showSpecialWorkspaces: Config.options.overview.showSpecialWorkspaces
    property var configuredSpecialWorkspaces: Config.options.overview.specialWorkspaces ?? []
    property var allWorkspaces: HyprlandData.allWorkspaces
    property bool previewsEnabled: Config.options.overview.previewsEnabled
    property string previewMode: {
        const mode = `${Config.options.overview.previewMode ?? "live"}`.trim().toLowerCase()
        return (mode === "event" || mode === "snapshot") ? "event" : "live"
    }
    property bool useEventPreviewRefresh: previewsEnabled && previewMode === "event"
    property int previewRecaptureToken: 0

    property real panelOpacity: Math.max(0, Math.min(1, Config.options.overview.effects.panelOpacity))
    property real workspaceOpacity: Math.max(0, Math.min(1, Config.options.overview.effects.workspaceOpacity))
    property bool glassMode: Config.options.overview.effects.glassMode
    property real glassTintStrength: Math.max(0, Math.min(1, Config.options.overview.effects.glassTintStrength))
    property real glassBorderOpacity: Math.max(0, Math.min(1, Config.options.overview.effects.glassBorderOpacity))
    property real glassShineOpacity: Math.max(0, Math.min(1, Config.options.overview.effects.glassShineOpacity))
    property real effectivePanelOpacity: glassMode ? Math.min(panelOpacity, 0.72) : panelOpacity
    property real effectiveWorkspaceOpacity: glassMode ? Math.min(workspaceOpacity, 0.55) : workspaceOpacity

    property real workspaceImplicitWidth: Math.round(
        (monitorData?.transform % 2 === 1)
            ? ((monitor.height / monitor.scale - (monitorData?.reserved?.[0] ?? 0) - (monitorData?.reserved?.[2] ?? 0)) * root.scale)
            : ((monitor.width  / monitor.scale - (monitorData?.reserved?.[0] ?? 0) - (monitorData?.reserved?.[2] ?? 0)) * root.scale)
    )
    property real workspaceImplicitHeight: Math.round(
        (monitorData?.transform % 2 === 1)
            ? ((monitor.width  / monitor.scale - (monitorData?.reserved?.[1] ?? 0) - (monitorData?.reserved?.[3] ?? 0)) * root.scale)
            : ((monitor.height / monitor.scale - (monitorData?.reserved?.[1] ?? 0) - (monitorData?.reserved?.[3] ?? 0)) * root.scale)
    )

    // Workspaces shown: active workspace always + any workspace with windows
    readonly property var visibleWorkspaceIds: {
        const active = Math.max(1, Math.min(100, monitor?.activeWorkspace?.id ?? 1))
        const ids = new Set([active])
        for (const addr in windowByAddress) {
            const win = windowByAddress[addr]
            const wsId = win?.workspace?.id
            const wsName = `${win?.workspace?.name ?? ""}`
            if (wsId !== undefined && !wsName.startsWith("special:"))
                ids.add(wsId)
        }
        return Array.from(ids).sort((a, b) => a - b)
    }

    readonly property var monitorSpecialWorkspaceNames: {
        const names = []
        for (const ws of (allWorkspaces ?? [])) {
            const name = `${ws?.name ?? ""}`
            if (!name.startsWith("special:")) continue
            if (`${ws?.monitor ?? ""}` !== `${root.monitor?.name ?? ""}`) continue
            names.push(name.slice(8))
        }
        return names
    }

    readonly property var specialWorkspaceNamesFromWindows: {
        const names = []
        for (const addr in windowByAddress) {
            const win = windowByAddress[addr]
            if ((win?.monitor ?? -1) !== (root.monitor?.id ?? -1)) continue
            const wsName = `${win?.workspace?.name ?? ""}`
            if (!wsName.startsWith("special:")) continue
            names.push(wsName.slice(8))
        }
        return names
    }

    readonly property var visibleSpecialWorkspaces: {
        if (!showSpecialWorkspaces) return []
        const out = []
        const pushUnique = v => {
            const s = `${v ?? ""}`.trim()
            if (s.length > 0 && !out.includes(s)) out.push(s)
        }
        for (const c of configuredSpecialWorkspaces) pushUnique(c)
        for (const n of monitorSpecialWorkspaceNames) pushUnique(n)
        for (const n of specialWorkspaceNamesFromWindows) pushUnique(n)
        return out
    }

    function getWindowsForWorkspace(wsId) {
        const wins = []
        for (const addr in windowByAddress) {
            const win = windowByAddress[addr]
            if ((win?.workspace?.id ?? -1) === wsId) wins.push(win)
        }
        return wins
    }

    function getWindowsForSpecialWorkspace(name) {
        const wins = []
        for (const addr in windowByAddress) {
            const win = windowByAddress[addr]
            if ((win?.monitor ?? -1) !== (root.monitor?.id ?? -1)) continue
            if (`${win?.workspace?.name ?? ""}` === `special:${name}`) wins.push(win)
        }
        return wins
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!GlobalStates.overviewOpen || !root.useEventPreviewRefresh) return
            const name = `${event?.name ?? event?.event ?? event?.type ?? ""}`
            if (name === "closewindow" || name === "openwindow" || name === "movewindow")
                root.previewRecaptureToken += 1
        }
    }

    implicitWidth: overviewBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: overviewBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

    StyledRectangularShadow { target: overviewBackground }

    Rectangle {
        id: overviewBackground
        property real padding: Config.options.overview.backgroundPadding
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        implicitWidth: contentLayout.implicitWidth + padding * 2
        implicitHeight: contentLayout.implicitHeight + padding * 2
        radius: (Appearance.rounding.screenRounding * root.scale + padding) * 1.5
        clip: true
        color: ColorUtils.applyAlpha(
            root.glassMode
                ? ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.85 - root.glassTintStrength * 0.40)
                : Appearance.colors.colLayer0,
            root.effectivePanelOpacity
        )
        border.width: 1
        border.color: ColorUtils.applyAlpha(
            root.glassMode
                ? ColorUtils.mix(Appearance.colors.colLayer0Border, Appearance.m3colors.m3outline, 0.40)
                : Appearance.colors.colLayer0Border,
            root.glassMode ? root.glassBorderOpacity * 0.5 : root.effectivePanelOpacity
        )

        Rectangle {
            visible: root.glassMode
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: ColorUtils.applyAlpha("#FFFFFF", root.glassShineOpacity * 0.25) }
                GradientStop { position: 0.35; color: ColorUtils.applyAlpha("#FFFFFF", 0.0) }
                GradientStop { position: 1.0; color: ColorUtils.applyAlpha("#000000", root.glassShineOpacity * 0.15) }
            }
        }

        Rectangle {
            visible: root.glassMode
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(parent.radius - 1, 0)
            color: "transparent"
            border.width: 1
            border.color: ColorUtils.applyAlpha("#FFFFFF", root.glassBorderOpacity * 0.12)
        }

        ColumnLayout {
            id: contentLayout
            anchors.centerIn: parent
            spacing: 0

            // ── Main workspace row ──────────────────────────────────────────
            RowLayout {
                id: mainRow
                spacing: root.workspaceSpacing

                Repeater {
                    model: ScriptModel { values: root.visibleWorkspaceIds }
                    delegate: Rectangle {
                        id: workspaceTile
                        required property var modelData
                        required property int index
                        property int wsId: modelData
                        property bool isActive: wsId === (root.monitor?.activeWorkspace?.id ?? -1)
                        property var tileWindows: root.getWindowsForWorkspace(wsId)

                        implicitWidth: root.workspaceImplicitWidth
                        implicitHeight: root.workspaceImplicitHeight
                        radius: Appearance.rounding.screenRounding * root.scale
                        clip: true
                        color: ColorUtils.applyAlpha(
                            root.glassMode
                                ? ColorUtils.mix(Appearance.colors.colLayer1, Appearance.colors.colLayer0, 0.55)
                                : Appearance.colors.colLayer1,
                            root.effectiveWorkspaceOpacity
                        )
                        border.width: isActive ? 1.5 : 1
                        border.color: isActive
                            ? root.activeBorderColor
                            : ColorUtils.applyAlpha(Appearance.colors.colLayer0Border, 0.2)

                        Rectangle {
                            visible: root.glassMode
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: ColorUtils.applyAlpha("#FFFFFF", root.glassShineOpacity * 0.15) }
                                GradientStop { position: 0.4; color: ColorUtils.applyAlpha("#FFFFFF", 0.0) }
                                GradientStop { position: 1.0; color: ColorUtils.applyAlpha("#000000", root.glassShineOpacity * 0.10) }
                            }
                        }

                        // Window previews
                        Repeater {
                            model: ScriptModel {
                                values: ToplevelManager.toplevels.values.filter(tl => {
                                    const addr = `0x${tl.HyprlandToplevel.address}`
                                    const win = root.windowByAddress[addr]
                                    return (win?.workspace?.id ?? -1) === workspaceTile.wsId
                                }).sort((a, b) => {
                                    const winA = root.windowByAddress[`0x${a.HyprlandToplevel.address}`]
                                    const winB = root.windowByAddress[`0x${b.HyprlandToplevel.address}`]
                                    return (winB?.focusHistoryID ?? 0) - (winA?.focusHistoryID ?? 0)
                                })
                            }
                            delegate: OverviewWindow {
                                id: winPreview
                                required property var modelData
                                property var address: `0x${modelData.HyprlandToplevel.address}`
                                property var winMonitorId: windowData?.monitor
                                property var winMonitor: HyprlandData.monitors.find(m => m.id === winMonitorId)
                                windowData: root.windowByAddress[address]
                                toplevel: modelData
                                monitorData: winMonitor
                                widgetMonitorData: root.monitorData
                                scale: root.scale
                                availableWorkspaceWidth: root.workspaceImplicitWidth
                                availableWorkspaceHeight: root.workspaceImplicitHeight
                                widgetMonitorId: root.monitor.id
                                xOffset: 0
                                yOffset: 0
                                recaptureToken: root.previewRecaptureToken

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: winPreview.hovered = true
                                    onExited: winPreview.hovered = false
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                    onClicked: event => {
                                        if (!winPreview.windowData) return
                                        if (event.button === Qt.LeftButton) {
                                            GlobalStates.overviewOpen = false
                                            Hyprland.dispatch(`focuswindow address:${winPreview.windowData.address}`)
                                        } else if (event.button === Qt.MiddleButton) {
                                            Hyprland.dispatch(`closewindow address:${winPreview.windowData.address}`)
                                        }
                                        event.accepted = true
                                    }
                                    StyledToolTip {
                                        extraVisibleCondition: false
                                        alternativeVisibleCondition: parent.containsMouse
                                        text: `${winPreview.windowData?.title ?? "Unknown"}\n[${winPreview.windowData?.class ?? "unknown"}]${winPreview.windowData?.xwayland ? " [XWayland]" : ""}`
                                    }
                                }
                            }
                        }

                        // App icon strip
                        TileIconStrip {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            windows: workspaceTile.tileWindows
                            tileScale: root.scale
                        }

                        // Workspace click target (behind window previews)
                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            acceptedButtons: Qt.LeftButton
                            onClicked: {
                                GlobalStates.overviewOpen = false
                                Hyprland.dispatch(`workspace ${workspaceTile.wsId}`)
                            }
                        }
                    }
                }
            }

            // ── Special workspace strip (only when populated) ───────────────
            Loader {
                Layout.alignment: Qt.AlignHCenter
                active: root.showSpecialWorkspaces && root.visibleSpecialWorkspaces.length > 0
                visible: active
                sourceComponent: ColumnLayout {
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: root.workspaceSpacing * 1.5
                    }

                    RowLayout {
                        spacing: root.workspaceSpacing

                        Repeater {
                            model: ScriptModel { values: root.visibleSpecialWorkspaces }
                            delegate: Rectangle {
                                id: specialTile
                                required property var modelData
                                property string specialName: modelData
                                property var specialWindows: root.getWindowsForSpecialWorkspace(specialName)
                                property bool isFocused: specialName === root.panelWindow.focusedSpecialWorkspace
                                property color baseColor: ColorUtils.mix(Appearance.colors.colLayer1, Appearance.colors.colLayer0, 0.52)

                                implicitWidth: root.workspaceImplicitWidth
                                implicitHeight: root.workspaceImplicitHeight
                                radius: Appearance.rounding.screenRounding * root.scale
                                clip: true
                                color: ColorUtils.applyAlpha(
                                    root.glassMode
                                        ? ColorUtils.mix(baseColor, Appearance.colors.colLayer0, 0.55)
                                        : baseColor,
                                    root.effectiveWorkspaceOpacity
                                )
                                border.width: isFocused ? 2 : 1
                                border.color: isFocused
                                    ? root.activeBorderColor
                                    : ColorUtils.applyAlpha(Appearance.colors.colLayer2Border, root.glassMode ? root.glassBorderOpacity * 0.4 : 0.55)

                                // Window previews
                                Repeater {
                                    model: ScriptModel {
                                        values: ToplevelManager.toplevels.values.filter(tl => {
                                            const addr = `0x${tl.HyprlandToplevel.address}`
                                            const win = root.windowByAddress[addr]
                                            if ((win?.monitor ?? -1) !== (root.monitor?.id ?? -1)) return false
                                            return `${win?.workspace?.name ?? ""}` === `special:${specialTile.specialName}`
                                        })
                                    }
                                    delegate: OverviewWindow {
                                        id: specialWinPreview
                                        required property var modelData
                                        property var address: `0x${modelData.HyprlandToplevel.address}`
                                        property var winMonitorId: windowData?.monitor
                                        property var winMonitor: HyprlandData.monitors.find(m => m.id === winMonitorId)
                                        windowData: root.windowByAddress[address]
                                        toplevel: modelData
                                        monitorData: winMonitor
                                        widgetMonitorData: root.monitorData
                                        scale: root.scale
                                        availableWorkspaceWidth: root.workspaceImplicitWidth
                                        availableWorkspaceHeight: root.workspaceImplicitHeight
                                        widgetMonitorId: root.monitor.id
                                        xOffset: 0
                                        yOffset: 0
                                        recaptureToken: root.previewRecaptureToken

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onEntered: specialWinPreview.hovered = true
                                            onExited: specialWinPreview.hovered = false
                                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                            onClicked: event => {
                                                if (!specialWinPreview.windowData) return
                                                if (event.button === Qt.LeftButton) {
                                                    GlobalStates.overviewOpen = false
                                                    Hyprland.dispatch(`focuswindow address:${specialWinPreview.windowData.address}`)
                                                } else if (event.button === Qt.MiddleButton) {
                                                    Hyprland.dispatch(`closewindow address:${specialWinPreview.windowData.address}`)
                                                }
                                                event.accepted = true
                                            }
                                            StyledToolTip {
                                                extraVisibleCondition: false
                                                alternativeVisibleCondition: parent.containsMouse
                                                text: `${specialWinPreview.windowData?.title ?? "Unknown"}\n[${specialWinPreview.windowData?.class ?? "unknown"}]`
                                            }
                                        }
                                    }
                                }

                                TileIconStrip {
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    windows: specialTile.specialWindows
                                    tileScale: root.scale
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    z: -1
                                    acceptedButtons: Qt.LeftButton
                                    onClicked: {
                                        GlobalStates.overviewOpen = false
                                        Hyprland.dispatch(`togglespecialworkspace ${specialTile.specialName}`)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
