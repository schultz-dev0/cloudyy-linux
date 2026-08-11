import QtQuick
import Quickshell
import "modules/island" as QuickIsland

// Task 12 runtime contract: injected page content must fill its slot.
ShellRoot {
    id: root

    property int failures: 0

    function near(actual, expected, label) {
        if (Math.abs(actual - expected) <= 1)
            return;
        failures++;
        console.error(`TASK12_ISLAND_LAYOUT_FAIL ${label}: expected ~${expected}, got ${actual}`);
    }

    // Mirrors the compact carousel viewport (610 wide, 142 - 2x14 margins).
    Item {
        id: host
        width: 610
        height: 114

        QuickIsland.IslandPageFrame {
            id: frame
            anchors.fill: parent

            // Same unsized-wrapper pattern the pages use.
            leftContent: Item {
                id: leftWrapper
            }
            rightContent: Item {
                id: rightWrapper
            }
        }
    }

    Timer {
        interval: 100
        repeat: false
        running: true
        onTriggered: {
            const slotWidth = (610 - frame.outerPadding * 2 - frame.dividerWidth) / 2;
            const leftPos = leftWrapper.mapToItem(host, 0, 0);
            root.near(leftPos.x, frame.outerPadding, "left wrapper x");
            root.near(leftPos.y, 0, "left wrapper y");
            root.near(leftWrapper.width, slotWidth, "left wrapper fills slot width");
            root.near(leftWrapper.height, host.height, "left wrapper fills slot height");
            const rightPos = rightWrapper.mapToItem(host, 0, 0);
            root.near(rightPos.x, 610 - frame.outerPadding - slotWidth, "right wrapper x");
            root.near(rightPos.y, 0, "right wrapper y");
            root.near(rightWrapper.width, slotWidth, "right wrapper fills slot width");
            root.near(rightWrapper.height, host.height, "right wrapper fills slot height");
            if (root.failures === 0)
                console.info("TASK12_ISLAND_LAYOUT_PASS");
            Qt.quit();
        }
    }
}
