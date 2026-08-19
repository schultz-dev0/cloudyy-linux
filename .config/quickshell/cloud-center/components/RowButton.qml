import QtQuick
import Quickshell
import "../services" as S
import ".."

RowBase {
    id: buttonRow

    Rectangle {
        width: buttonText.implicitWidth + 24; height: 26; radius: 2
        color: btnHover.hovered ? Theme.glass(Theme.primary, 0.14) : Theme.glass(Theme.primary, 0.08)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text { id: buttonText; anchors.centerIn: parent
               text: buttonRow.item.button_text || "Open ›"
               color: Theme.accent; font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 } }
        HoverHandler { id: btnHover }
        TapHandler {
            onTapped: S.Backend.request("run_action", { item: buttonRow.item.id }, function(result) {
                if (!result) return;
                if (result.navigate)
                    S.Nav.navigate(result.navigate);
                else if (result.open === "bezier_editor" || result.builtin === "bezier_editor")
                    S.Backend.requestBezierEditor();
            });
        }
    }
}
