import QtQuick
import ".."   // Theme via parent dir of components/ = config root; adjust to "../.." if symlink route was taken

Rectangle {
    radius: Theme.glassPanelRadius
    color: Theme.glass(Theme.surface_container, 0.62)
    border.width: 1
    border.color: Theme.glassPanelBorder
}
