import QtQuick
import "../.."

// Shared compact composition; page children own typography and rendering.
Item {
    id: root

    default property alias leftContent: leftSlot.data
    property alias rightContent: rightSlot.data
    property alias compactContent: leftSlot.data
    property alias expandedContent: rightSlot.data

    readonly property int outerPadding: 16
    readonly property int dividerWidth: 1

    // Pages inject an unsized wrapper Item per slot; without this, every
    // parent-anchored layout inside pages collapses onto the slot origin.
    function _fillSlot(slot) {
        for (let i = 0; i < slot.children.length; i++) {
            const child = slot.children[i];
            if (child && child.anchors && child.anchors.fill !== slot)
                child.anchors.fill = slot;
        }
    }

    Item {
        id: leftSlot
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            leftMargin: root.outerPadding
        }
        width: Math.max(0, (parent.width - root.outerPadding * 2 - root.dividerWidth) / 2)

        onChildrenChanged: root._fillSlot(leftSlot)
    }

    Rectangle {
        id: divider
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: leftSlot.right
        }
        width: root.dividerWidth
        color: Theme.islandBorder
    }

    Item {
        id: rightSlot
        anchors {
            top: parent.top
            right: parent.right
            bottom: parent.bottom
            rightMargin: root.outerPadding
            left: divider.right
        }

        onChildrenChanged: root._fillSlot(rightSlot)
    }
}
