import QtQuick
import "DockFitPolicy.js" as DockFitPolicy

QtObject {
    id: root

    property real screenWidth: 0
    property int appCount: 0
    property int folderCount: 0

    readonly property real baseIconSize: 48
    readonly property real baseIconSpacing: 25
    readonly property real basePaddingH: 14
    readonly property real basePaddingV: 12
    readonly property real edgeMargin: 12
    readonly property real fixedWidth: 2

    readonly property real naturalIconsWidth: Math.max(0, root.appCount) * root.baseIconSize
        + Math.max(0, root.appCount - 1) * root.baseIconSpacing
    readonly property real naturalFoldersWidth: Math.max(0, root.folderCount) * root.baseIconSize
        + Math.max(0, root.folderCount - 1) * root.baseIconSpacing
    readonly property real naturalScalableWidth: root.basePaddingH * 2 + root.baseIconSize * 2
        + root.baseIconSpacing * 5 + root.naturalIconsWidth + root.naturalFoldersWidth
    readonly property real naturalDockWidth: root.naturalScalableWidth + root.fixedWidth

    readonly property real fitScale: DockFitPolicy.fitScale(
        root.screenWidth, root.naturalScalableWidth, root.fixedWidth, root.edgeMargin)
    readonly property real iconSize: root.baseIconSize * root.fitScale
    readonly property real iconSpacing: root.baseIconSpacing * root.fitScale
    readonly property real paddingH: root.basePaddingH * root.fitScale
    readonly property real paddingV: root.basePaddingV * root.fitScale

    readonly property real iconsWidth: Math.max(0, root.appCount) * root.iconSize
        + Math.max(0, root.appCount - 1) * root.iconSpacing
    readonly property real foldersWidth: Math.max(0, root.folderCount) * root.iconSize
        + Math.max(0, root.folderCount - 1) * root.iconSpacing
    readonly property real dockWidth: root.paddingH * 2 + root.iconSize * 2
        + root.iconSpacing * 5 + root.iconsWidth + root.foldersWidth + root.fixedWidth
    readonly property real availableWidth: root.screenWidth > 0
        ? Math.max(0, root.screenWidth - root.edgeMargin * 2)
        : root.naturalDockWidth
    readonly property bool fitsAvailableWidth: root.dockWidth <= root.availableWidth + 0.001
}
