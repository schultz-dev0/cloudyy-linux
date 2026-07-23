import QtQuick
import "../components"
import "../services" as S
import ".."

Flickable {
    id: yamlPage
    required property var page
    contentHeight: pageColumn.implicitHeight + 48
    clip: true

    // The Loader keeps this same YamlPage instance alive across yaml→yaml
    // navigation (sourceComponent doesn't change), so onCompleted/onDestruction
    // alone would only ever subscribe once. Track which page id we're
    // subscribed to and re-subscribe whenever `page` changes underneath us.
    property string subscribedPageId: ""

    function resubscribe() {
        if (subscribedPageId !== "")
            S.Backend.request("unsubscribe", { page: subscribedPageId }, null);
        subscribedPageId = page.id;
        S.Backend.request("subscribe", { page: subscribedPageId }, null);
    }

    Component.onCompleted: resubscribe()
    onPageChanged: resubscribe()
    Component.onDestruction: {
        if (subscribedPageId !== "")
            S.Backend.request("unsubscribe", { page: subscribedPageId }, null);
    }

    Column {
        id: pageColumn
        width: Math.min(yamlPage.width - 56, 720)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 16
        topPadding: 24

        Text { text: yamlPage.page.title; color: Theme.textPrimary
               font { family: "JetBrainsMono Nerd Font"; pixelSize: 20; bold: true } }

        Repeater {
            model: yamlPage.page.sections
            delegate: SectionCard {
                required property var modelData
                width: pageColumn.width
                section: modelData
                Repeater {
                    model: modelData.items
                    delegate: Loader {
                        required property var modelData
                        width: parent.width
                        sourceComponent: {
                            switch (modelData.type) {
                            case "label":            return labelComp;
                            case "button":           return buttonComp;
                            case "toggle":           return toggleComp;
                            case "slider":           return sliderComp;
                            case "selection":        return selectComp;
                            case "multi_selection":  return multiComp;
                            case "wallpaper_picker": return wallpaperComp;
                            case "online_wallpaper_browser": return onlineWallpaperComp;
                            case "extension_browser": return extensionBrowserComp;
                            default:                 return unsupportedComp;
                            }
                        }
                        property Component labelComp: Component { RowLabel { item: modelData } }
                        property Component buttonComp: Component { RowButton { item: modelData } }
                        property Component toggleComp: Component { RowToggle { item: modelData } }
                        property Component sliderComp: Component { RowSlider { item: modelData } }
                        property Component selectComp: Component { RowSelect { item: modelData } }
                        property Component multiComp: Component { RowMultiSelect { item: modelData } }
                        property Component wallpaperComp: Component { WallpaperGrid { item: modelData } }
                        property Component onlineWallpaperComp: Component { OnlineWallpaperBrowser { item: modelData } }
                        property Component extensionBrowserComp: Component { ExtensionBrowser { item: modelData } }
                        property Component unsupportedComp: Component {
                            RowBase { item: modelData
                                Text { text: modelData.type; color: Theme.textMuted
                                       font.family: "JetBrainsMono Nerd Font" } } }
                    }
                }
            }
        }
    }
}
