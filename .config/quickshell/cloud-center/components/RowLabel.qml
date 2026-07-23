import QtQuick
import "../services" as S
import ".."

RowBase {
    id: labelRow
    property string liveText: item.text ?? "…"
    Text { text: labelRow.liveText; color: Theme.textMuted
           font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 } }
    Connections {
        target: S.Backend
        function onLabelEvent(itemId, text) {
            if (itemId === labelRow.item.id) labelRow.liveText = text;
        }
    }
}
