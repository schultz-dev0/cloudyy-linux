import QtQuick
import "../services" as S
import ".."

RowBase {
    id: toggleRow
    property bool checked: item.value === true

    Rectangle {
        width: 40; height: 22; radius: 11
        color: toggleRow.checked ? Theme.primary : Theme.outline_variant
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            x: toggleRow.checked ? parent.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16; radius: 8
            color: Theme.surface_container_lowest
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
        TapHandler {
            onTapped: {
                toggleRow.checked = !toggleRow.checked;   // optimistic
                S.Backend.request("run_action",
                    { item: toggleRow.item.id, value: toggleRow.checked }, null);
            }
        }
    }
    Connections {
        target: S.Backend
        function onStateEvent(itemId, key, value) {
            if (itemId === toggleRow.item.id) toggleRow.checked = value;
        }
    }
}
