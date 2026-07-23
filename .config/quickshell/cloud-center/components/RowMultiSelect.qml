import QtQuick
import "../services" as S
import ".."

Column {
    id: multi
    required property var item
    property var selected: item.values ?? []
    property bool expanded: false
    width: parent ? parent.width : 0

    RowBase {
        item: multi.item
        Text { text: multi.selected.join(", ") || "None"
               color: Theme.textMuted; font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 } }
        Text { text: multi.expanded ? "▾" : "▸"; color: Theme.textMuted
               font.family: "JetBrainsMono Nerd Font" }
        onClicked: multi.expanded = !multi.expanded
    }
    Repeater {
        model: multi.expanded ? (multi.item.options ?? []) : []
        delegate: RowBase {
            required property string modelData
            item: ({ id: multi.item.id, title: modelData })
            Rectangle {   // simple check indicator
                width: 16; height: 16; radius: 4
                color: multi.selected.includes(modelData) ? Theme.primary : Theme.outline_variant
                TapHandler {
                    onTapped: {
                        let next = multi.selected.filter(v => v !== modelData);
                        if (next.length === multi.selected.length) next.push(modelData);
                        if (next.length === 0) return;   // min one stays enabled
                        multi.selected = next;
                        S.Backend.request("run_action",
                            { item: multi.item.id, values: next }, null);
                    }
                }
            }
        }
    }
}
