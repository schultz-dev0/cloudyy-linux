import QtQuick
import "../components"
import "../services" as S
import ".."

Flickable {
    id: results
    contentHeight: col.implicitHeight + 48
    clip: true

    readonly property var matches: {
        const q = S.Nav.searchQuery.toLowerCase();
        const found = [];
        if (!S.Nav.model || q === "") return found;
        for (const page of S.Nav.model.pages) {
            if (page.kind !== "yaml") continue;
            for (const section of page.sections)
                for (const item of section.items) {
                    const hay = ((item.title ?? "") + " " + (item.description ?? "")).toLowerCase();
                    if (hay.includes(q))
                        found.push({ pageId: page.id, pageTitle: page.title, item: item });
                }
        }
        return found;
    }

    Column {
        id: col
        width: Math.min(results.width - 56, 720)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6; topPadding: 24

        Text { text: results.matches.length + " results"
               color: Theme.textMuted; font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 } }
        Repeater {
            model: results.matches
            delegate: RowBase {
                required property var modelData
                item: modelData.item
                Text { text: modelData.pageTitle + " ›"
                       color: Theme.textMuted; font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 } }
                onClicked: S.Nav.navigate(modelData.pageId)
            }
        }
    }
}
