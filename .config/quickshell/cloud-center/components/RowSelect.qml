import QtQuick
import "../services" as S
import ".."

RowBase {
    id: selectRow
    readonly property var options: item.options ?? []
    CloudSelect {
        id: combo
        width: 160
        compact: true
        options: selectRow.options
        currentIndex: Math.max(0, selectRow.options.indexOf(selectRow.item.value))
        onActivated: index => S.Backend.request("run_action",
            { item: selectRow.item.id, value: selectRow.options[index] }, null)
    }
}
